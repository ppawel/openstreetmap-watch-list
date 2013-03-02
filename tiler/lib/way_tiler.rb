require 'logging'
require 'utils'
require 'geos_utils'
require 'ffi-geos'

module Tiler

# Implements tiling logic for way revisions.
class WayTiler
  include ::Tiler::Logger

  attr_accessor :conn

  def initialize(conn)
    @zoom = 16
    @tiledata = {}
    @conn = conn
    @wkb_reader = Geos::WkbReader.new
    @wkt_reader = Geos::WktReader.new
    @wkb_writer = Geos::WkbWriter.new
    @wkb_writer.include_srid = true
    @wkt_writer = Geos::WktWriter.new
    setup_prepared_statements
  end

  def create_way_tiles(way_id, changeset_id = nil, ensure_revisions = true)
    @@log.debug "Way #{way_id}"

    if ensure_revisions
      ensure_way_revisions(way_id)
      @@log.debug "  revisions ensured"
    end

    revs = @conn.exec_prepared('select_revisions', [way_id, changeset_id]).to_a
    @@log.debug "  revisions count = #{revs.size}"

    @prev = nil

    for rev in revs
      if !rev['geom']
        @@log.warn "  version #{rev['version']} rev #{rev['rev']} -- NO GEOMETRY"
        next
      end

      rev['geom_obj'] = @wkb_reader.read_hex(rev['geom'])
      @@log.debug "  version #{rev['version']} rev #{rev['rev']}"

      diff_bbox = nil
      same_geom = false
      if @prev and @prev['geom_obj']
        same_geom = rev['geom_obj'].equals?(@prev['geom_obj'])
        diff_bbox = envelope_to_bbox(rev['geom_obj'].sym_difference(@prev['geom_obj']).envelope) if not same_geom
      end

      count = create_rev_tiles(rev, diff_bbox, same_geom)
      @@log.debug "    Created #{count} tile(s)"

      @prev['geom_obj'] = nil if @prev
      @prev = rev

      # GC has problems if we don't do this explicitly...
      #@prev['geom_obj'] = nil
    end
  end

  private

  def create_rev_tiles(rev, diff_bbox, same_geom)
    return -1 if has_tiles(rev)

    count = 0
    geom = rev['geom_obj']
    geom_prep = rev['geom_obj'].to_prepared
    bbox = box2d_to_bbox(rev['bbox'])
    tile_count = bbox_tile_count(@zoom, bbox)
    diff_tile_count = bbox_tile_count(@zoom, diff_bbox) if diff_bbox

    @@log.debug "    tile_count = #{tile_count}, diff_tile_count = #{diff_tile_count}, same_geom = #{same_geom}"

    if tile_count == 1
      tile = bbox_to_tiles(@zoom, bbox).to_a[0]
      insert_tile(rev, tile[0], tile[1], geom)
      return 1
    elsif same_geom
      return @conn.exec("INSERT INTO way_tiles
        SELECT way_id, version, #{rev['rev']}, changeset_id, tstamp, x, y, geom
        FROM way_tiles WHERE way_id = #{rev['way_id']} AND rev = #{rev['rev'].to_i - 1}").cmd_tuples
    elsif diff_tile_count and (diff_tile_count < 0.90 * tile_count)
      bounds = bbox_bound_tiles(@zoom, diff_bbox)
      tiles = bbox_to_tiles(@zoom, diff_bbox)
      count = @conn.exec("INSERT INTO way_tiles
        SELECT way_id, version, #{rev['rev']}, changeset_id, tstamp, x, y, geom
        FROM way_tiles WHERE way_id = #{rev['way_id']} AND rev = #{rev['rev'].to_i - 1} AND
        NOT (x >= #{bounds[0][0]} AND x <= #{bounds[1][0]} AND y >= #{bounds[0][1]} AND y <= #{bounds[1][1]})").cmd_tuples
    elsif tile_count < 64
      # Does not make sense to try to reduce small geoms.
      tiles = bbox_to_tiles(@zoom, bbox)
    else
      tiles_to_check = (tile_count < 2048 ? bbox_to_tiles(14, bbox) : prepare_tiles_to_check(geom_prep, bbox, 14))
      @@log.debug "    tiles_to_check = #{tiles_to_check.size}"
      tiles = prepare_tiles(tiles_to_check, geom_prep, 14, @zoom)
    end

    @@log.debug "    Processing #{tiles.size} tile(s)..."

    tiles.each_with_index do |tile, index|
      x, y = tile[0], tile[1]
      tile_geom = get_tile_geom(x, y, @zoom)

      if geom_prep.intersects?(tile_geom)
        intersection = geom.intersection(tile_geom)
        intersection.srid = 4326
        if !intersection.empty?
          insert_tile(rev, x, y, intersection)
          count += 1
        else
          @@log.warn "    Empty tile: #{tile} #{@wkt_writer.write(tile_geom)}\n#{@wkt_writer.write(geom_prep)}"
        end
      end

      if index > 0 and index % 1000 == 0
        @@log.debug "    i = #{index}, created tiles = #{count}"
      end
    end
    count
  end

  def insert_tile(rev, x, y, geom)
    @conn.exec_prepared('insert_way_tile', [rev['way_id'], rev['version'], rev['rev'], rev['tstamp'],
      rev['changeset_id'], x, y, @wkb_writer.write_hex(geom)])
  end

  def has_tiles(rev)
    @conn.exec_prepared('has_tiles', [rev['way_id'], rev['rev']]).getvalue(0, 0).to_i > 0
  end

  def ensure_way_revisions(way_id)
    @conn.exec("SELECT OWL_UpdateWayRevisions(#{way_id})")
  end

  def setup_prepared_statements
    @conn.prepare('select_revisions',
      "SELECT q.*, q.line::box2d AS bbox,
        CASE
          WHEN GeometryType(q.line) = 'LINESTRING' AND ST_IsClosed(q.line) AND ST_IsSimple(q.line)
          THEN ST_ForceRHR(ST_MakePolygon(q.line))
          ELSE q.line
        END AS geom
      FROM (
        SELECT
          rev.geom AS line, --OWL_MakeLine(w.nodes, rev.tstamp) AS line,
          rev.*
        FROM way_revisions rev
        LEFT JOIN way_revisions prev ON (prev.way_id = rev.way_id AND prev.rev = rev.rev + 1)
        INNER JOIN ways w ON (w.id = rev.way_id AND w.version = rev.version)
        WHERE rev.way_id = $1 AND ($2::int IS NULL OR rev.changeset_id = $2 OR prev.changeset_id = $2) AND
          NOT EXISTS (SELECT 1 FROM way_tiles wt WHERE wt.way_id = rev.way_id AND wt.rev = rev.rev LIMIT 1)) q
      ORDER BY q.way_id, q.rev")

    @conn.prepare('has_tiles', "SELECT COUNT(*) FROM way_tiles WHERE way_id = $1 AND rev = $2")

    @conn.prepare('insert_way_tile',
      "INSERT INTO way_tiles (way_id, version, rev, tstamp, changeset_id, x, y, geom) VALUES
        ($1, $2, $3, $4, $5, $6, $7, $8)")
  end
end

end
