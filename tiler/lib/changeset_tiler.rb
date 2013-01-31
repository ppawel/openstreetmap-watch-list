require 'logging'
require 'utils'
require 'ffi-geos'
require 'way_tiler'

module Tiler

# Implements tiling logic for changesets.
class ChangesetTiler
  include ::Tiler::Logger

  attr_accessor :conn

  def initialize(conn)
    @way_tiler = WayTiler.new(conn)
    @tiledata = {}
    @conn = conn
    setup_prepared_statements
  end

  ##
  # Generates tiles for given zoom and changeset.
  #
  def generate(zoom, changeset_id, options = {})
    tile_count = nil
    @@log.debug "mem = #{memory_usage} (before)"

    ensure_way_revisions(changeset_id)
    @conn.transaction do |c|
      generate_changes(changeset_id) if options[:changes] or !has_changes(changeset_id)
      tile_count = do_generate(zoom, changeset_id, options)
    end
    @@log.debug "mem = #{memory_usage} (after)"
    tile_count
  end

  ##
  # Removes tiles for given zoom and changeset. This is useful when retiling (creating new tiles) to avoid
  # duplicate primary key error during insert.
  #
  def clear_tiles(changeset_id, zoom)
    count = @conn.exec("DELETE FROM changeset_tiles WHERE changeset_id = #{changeset_id} AND zoom = #{zoom}").cmd_tuples
    @@log.debug "Removed existing tiles: #{count}"
    count
  end

  def has_tiles(changeset_id)
    @conn.exec("SELECT COUNT(*) FROM changeset_tiles WHERE changeset_id = #{changeset_id}").getvalue(0, 0).to_i > 0
  end

  def has_changes(changeset_id)
    @conn.exec("SELECT COUNT(*) FROM changes WHERE changeset_id = #{changeset_id}").getvalue(0, 0).to_i > 0
  end

  protected

  def do_generate(zoom, changeset_id, options = {})
    if options[:retile]
      clear_tiles(changeset_id, zoom)
    else
      return -1 if has_tiles(changeset_id)
    end
    for change in @conn.exec_prepared('select_changes', [changeset_id]).to_a
      @way_tiler.create_way_tiles(change['el_id'], changeset_id) if change['el_type'] == 'W'
    end
    @conn.exec_prepared('generate_changeset_tiles', [changeset_id]).cmd_tuples
  end

  def _do_generate(zoom, changeset_id, options = {})
    if options[:retile]
      clear_tiles(changeset_id, zoom)
    else
      return -1 if has_tiles(changeset_id)
    end

    for change in @conn.exec_prepared('select_changes', [changeset_id]).to_a
      change['geom_changed'] = (change['geom_changed'] == 't')
      if change['geom']
        change['geom_obj'] = @wkb_reader.read_hex(change['geom'])
        change['geom_obj_prep'] = change['geom_obj'].to_prepared
      end
      if change['prev_geom']
        change['prev_geom_obj'] = @wkb_reader.read_hex(change['prev_geom'])
        change['prev_geom_obj_prep'] = change['prev_geom_obj'].to_prepared
      end
      if change['diff_bbox']
        change['diff_geom_obj'] =  change['geom_obj'].difference(change['prev_geom_obj'])
        change['diff_geom_obj_prep'] = change['diff_geom_obj'].to_prepared
      end

      @@log.debug "#{change['el_type']} #{change['el_id']} (#{change['el_version']})"

      create_change_tiles(changeset_id, change, change['id'].to_i, zoom)

      # GC has problems if we don't do this explicitly...
      change['geom_obj'] = nil
      change['prev_geom_obj'] = nil
      change['diff_geom_obj'] = nil
    end

    @tiledata.each do |tile, data|
      @conn.exec_prepared('insert_tile', [changeset_id, data[:tstamp], tile[2], tile[0], tile[1],
          data[:changes].to_s.gsub("[", "{").gsub("]", "}"),
          to_postgres_geom_array(data[:geom]), to_postgres_geom_array(data[:prev_geom])])
    end

    @@log.debug "Aggregating tiles..."

    # Now generate tiles at lower zoom levels.
    (12..zoom).reverse_each do |i|
      @conn.exec("SELECT OWL_AggregateChangeset(#{changeset_id}, #{i}, #{i - 1})")
    end

    count = @tiledata.size
    free_tiles
    count
  end

  def ensure_way_revisions(changeset_id)
    @conn.exec("SELECT OWL_CreateWayRevisions(q.id) FROM (
      SELECT DISTINCT id FROM ways WHERE changeset_id = #{changeset_id} UNION
      SELECT DISTINCT id FROM ways WHERE nodes && (SELECT array_agg(id) FROM nodes WHERE changeset_id = #{changeset_id})) q")
  end

  def add_change_tile(x, y, zoom, change, geom, prev_geom)
    if !@tiledata.include?([x, y, zoom])
      @tiledata[[x, y, zoom]] = {
        :changes => [change['id'].dup.to_i],
        :tstamp => change['tstamp'].dup,
        :geom => [(geom ? @wkb_writer.write_hex(geom) : nil)],
        :prev_geom => [(prev_geom ? @wkb_writer.write_hex(prev_geom) : nil)]
      }
      return
    end

    @tiledata[[x, y, zoom]][:changes] << change['id'].dup.to_i
    @tiledata[[x, y, zoom]][:geom] << (geom ? @wkb_writer.write_hex(geom) : nil)
    @tiledata[[x, y, zoom]][:prev_geom] << (prev_geom ? @wkb_writer.write_hex(prev_geom) : nil)
  end

  def free_tiles
    @tiledata = {}
  end

  def create_change_tiles(changeset_id, change, change_id, zoom)
    if change['el_action'] == 'DELETE'
      count = create_geom_tiles(changeset_id, change, change['prev_geom_obj'], change['prev_geom_obj_prep'], change_id, zoom, true)
    else
      count = create_geom_tiles(changeset_id, change, change['geom_obj'], change['geom_obj_prep'], change_id, zoom, false)
      if change['geom_changed']
        count += create_geom_tiles(changeset_id, change, change['prev_geom_obj'], change['prev_geom_obj_prep'], change_id, zoom, true)
      end
    end

    @@log.debug "  Created #{count} tile(s)"
  end

  def create_geom_tiles(changeset_id, change, geom, geom_prep, change_id, zoom, is_prev)
    return 0 if geom.nil?

    if change['diff_bbox']
      bbox_to_use = 'diff_bbox'
    else
      bbox_to_use = (is_prev ? 'prev_geom' : 'geom') + '_bbox'
    end

    bbox = box2d_to_bbox(change[bbox_to_use])
    tile_count = bbox_tile_count(zoom, bbox)

    @@log.debug "  tile_count = #{tile_count} (using #{bbox_to_use})"

    if change['el_type'] == 'N'
      # Fast track a change that fits on a single tile (e.g. all nodes) - just create the tile.
      tiles = bbox_to_tiles(zoom, bbox)
      add_change_tile(tiles.to_a[0][0], tiles.to_a[0][1], zoom, change, is_prev ? nil : geom, is_prev ? geom : nil)
      return 1
    elsif tile_count < 64
      # Does not make sense to try to reduce small geoms.
      tiles = bbox_to_tiles(zoom, bbox)
    else
      tiles_to_check = (tile_count < 2048 ? bbox_to_tiles(14, bbox) : prepare_tiles_to_check(geom_prep, bbox, 14))
      @@log.debug "  tiles_to_check = #{tiles_to_check.size}"
      tiles = prepare_tiles(tiles_to_check, geom_prep, 14, zoom)
    end

    @@log.debug "  Processing #{tiles.size} tile(s)..."

    test_geom = change['diff_geom_obj_prep'] || geom_prep
    count = 0

    for tile in tiles
      x, y = tile[0], tile[1]
      tile_geom = get_tile_geom(x, y, zoom)

      if test_geom.intersects?(tile_geom)
        intersection = geom.intersection(tile_geom)
        intersection.srid = 4326
        add_change_tile(x, y, zoom, change, is_prev ? nil : intersection, is_prev ? intersection : nil)
        count += 1
      end
    end
    count
  end

  def generate_changes(changeset_id)
    @conn.exec_prepared('delete_changes', [changeset_id])
    @conn.exec_prepared('insert_changes', [changeset_id])
  end

  def setup_prepared_statements
    @conn.prepare('delete_changes', 'DELETE FROM changes WHERE changeset_id = $1')

    @conn.prepare('insert_changes', 'INSERT INTO changes
      (changeset_id, tstamp, el_changeset_id, el_type, el_id, el_version, el_rev, el_action,
        tags, prev_tags, nodes, prev_nodes)
      SELECT * FROM OWL_GenerateChanges($1)')

    @conn.prepare('select_changes', "SELECT * FROM changes WHERE changeset_id = $1")

    @conn.prepare('generate_changeset_tiles',
      "INSERT INTO changeset_tiles (changeset_id, tstamp, zoom, x, y, changes, geom, prev_geom)
      SELECT
        $1::int,
        MAX(q.tstamp),
        16,
        q.x,
        q.y,
        array_agg(q.change_id),
        array_agg(q.geom),
        array_agg(q.prev_geom)
      FROM (
        SELECT
          t.tstamp,
          t.x,
          t.y,
          c.id AS change_id,
          t.geom AS geom,
          CASE WHEN t.geom = prev_t.geom THEN NULL ELSE prev_t.geom END AS prev_geom
        FROM changes c
        INNER JOIN tiles t ON (t.el_type = c.el_type AND t.el_id = c.el_id AND t.el_rev = c.el_rev)
        INNER JOIN tiles prev_t ON (prev_t.el_type = c.el_type AND prev_t.el_id = c.el_id AND
          prev_t.el_rev = c.el_rev - 1 AND t.x = prev_t.x AND t.y = prev_t.y)
        WHERE c.changeset_id = $1 AND c.el_type = 'W'

          UNION

        SELECT
          t.tstamp,
          t.x,
          t.y,
          c.id AS change_id,
          t.geom AS geom,
          NULL AS prev_geom
        FROM changes c
        INNER JOIN tiles t ON (t.el_type = c.el_type AND t.el_id = c.el_id AND t.el_rev = c.el_rev)
        LEFT JOIN tiles prev_t ON (prev_t.el_type = c.el_type AND prev_t.el_id = c.el_id AND
          prev_t.el_rev = c.el_rev - 1 AND t.x = prev_t.x AND t.y = prev_t.y)
        WHERE c.changeset_id = $1 AND c.el_type = 'W' AND prev_t.x IS NULL

          UNION

        SELECT
          prev_t.tstamp,
          prev_t.x,
          prev_t.y,
          c.id AS change_id,
          NULL AS geom,
          prev_t.geom AS prev_geom
        FROM changes c
        INNER JOIN tiles prev_t ON (prev_t.el_type = c.el_type AND prev_t.el_id = c.el_id AND
          prev_t.el_rev = c.el_rev - 1)
        LEFT JOIN tiles t ON (t.el_type = c.el_type AND t.el_id = c.el_id AND t.el_rev = c.el_rev AND
          t.x = prev_t.x AND t.y = prev_t.y)
        WHERE c.changeset_id = $1 AND c.el_type = 'W' AND t.x IS NULL

          UNION

        SELECT
          q.tstamp,
          q.t_x,
          q.t_y,
          q.change_id AS change_id,
          q.geom,
          CASE WHEN q.geom = q.prev_geom OR t_x != prev_t_x OR t_y != prev_t_y THEN NULL ELSE prev_geom END AS prev_geom
        FROM (SELECT n.tstamp, n.geom, prev_n.geom AS prev_geom,
            (SELECT x FROM OWL_LatLonToTile(16, n.geom)) AS t_x,
            (SELECT y FROM OWL_LatLonToTile(16, n.geom)) AS t_y,
            (SELECT x FROM OWL_LatLonToTile(16, prev_n.geom)) AS prev_t_x,
            (SELECT y FROM OWL_LatLonToTile(16, prev_n.geom)) AS prev_t_y,
            c.id AS change_id
          FROM changes c
          INNER JOIN nodes n ON (n.id = c.el_id AND n.version = c.el_version)
          INNER JOIN nodes prev_n ON (prev_n.id = c.el_id AND prev_n.version = c.el_version - 1)
          WHERE c.changeset_id = $1 AND c.el_type = 'N') q

          UNION

        SELECT
          q.tstamp,
          q.t_x,
          q.t_y,
          q.change_id AS change_id,
          q.geom,
          CASE WHEN q.geom = q.prev_geom OR t_x != prev_t_x OR t_y != prev_t_y THEN NULL ELSE prev_geom END AS prev_geom
        FROM (SELECT n.tstamp, n.geom, prev_n.geom AS prev_geom,
            (SELECT x FROM OWL_LatLonToTile(16, n.geom)) AS t_x,
            (SELECT y FROM OWL_LatLonToTile(16, n.geom)) AS t_y,
            (SELECT x FROM OWL_LatLonToTile(16, prev_n.geom)) AS prev_t_x,
            (SELECT y FROM OWL_LatLonToTile(16, prev_n.geom)) AS prev_t_y,
            c.id AS change_id
          FROM changes c
          LEFT JOIN nodes n ON (n.id = c.el_id AND n.version = c.el_version)
          LEFT JOIN nodes prev_n ON (prev_n.id = c.el_id AND prev_n.version = c.el_version - 1)
          WHERE c.changeset_id = $1 AND c.el_type = 'N' AND (n.tstamp IS NULL OR prev_n.tstamp IS NULL) AND
            (n.tstamp IS NOT NULL OR prev_n.tstamp IS NOT NULL)) q
      ) q
      GROUP BY q.x, q.y")
  end
end

end
