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
    for change in @conn.exec_prepared('select_changes', [changeset_id]).to_a
      @way_tiler.create_way_tiles(change['el_id'], nil) if change['el_type'] == 'W'
    end
    @conn.exec_prepared('generate_changeset_tiles', [changeset_id])
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
          prev_t.el_rev = c.el_rev - 1 AND prev_t.x = t.x AND prev_t.y = t.y)
        WHERE c.changeset_id = $1 AND c.el_type = 'W'
          UNION
        SELECT
          CASE WHEN t.tstamp IS NULL THEN prev_t.tstamp ELSE t.tstamp END,
          CASE WHEN t.x IS NULL THEN prev_t.x ELSE t.x END,
          CASE WHEN t.y IS NULL THEN prev_t.y ELSE t.y END,
          c.id AS change_id,
          CASE WHEN t.geom IS NULL THEN prev_t.geom ELSE t.geom END,
          CASE WHEN prev_t.geom IS NULL THEN prev_t.geom ELSE t.geom END
        FROM changes c
        LEFT JOIN tiles t ON (t.el_type = c.el_type AND t.el_id = c.el_id AND t.el_rev = c.el_rev)
        LEFT JOIN tiles prev_t ON (prev_t.el_type = c.el_type AND prev_t.el_id = c.el_id AND prev_t.el_rev = c.el_rev - 1)
        WHERE c.changeset_id = $1 AND c.el_type = 'W' AND (t.tstamp IS NULL OR prev_t.tstamp IS NULL)
          UNION
        SELECT
          n.tstamp,
          (SELECT x FROM OWL_LatLonToTile(16, n.geom)),
          (SELECT y FROM OWL_LatLonToTile(16, n.geom)),
          c.id AS change_id,
          n.geom,
          NULL AS prev_geom
        FROM changes c
        INNER JOIN nodes n ON (c.el_id = n.id AND c.el_version = n.version)
        WHERE c.changeset_id = $1 AND c.el_type = 'N'
          UNION
        SELECT
          prev_n.tstamp,
          (SELECT x FROM OWL_LatLonToTile(16, prev_n.geom)),
          (SELECT y FROM OWL_LatLonToTile(16, prev_n.geom)),
          c.id AS change_id,
          NULL,
          prev_n.geom AS prev_geom
        FROM changes c
        INNER JOIN nodes prev_n ON (c.el_id = prev_n.id AND c.el_version = prev_n.version)
        WHERE c.changeset_id = $1 AND c.el_type = 'N'
      ) q
      GROUP BY q.x, q.y")
  end
end

end
