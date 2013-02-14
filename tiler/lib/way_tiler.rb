require 'logging'
require 'utils'
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
    setup_prepared_statements
  end

  def create_way_tiles(way_id, changeset_id = nil)
    @@log.debug "Way #{way_id}"

    ensure_way_revisions(way_id)
    @@log.debug "  revisions ensured"
    revs = @conn.exec_prepared('select_revisions', [way_id]).to_a
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
      if @prev and @prev['geom_obj']
        diff_bbox = envelope_to_bbox(rev['geom_obj'].sym_difference(@prev['geom_obj']).envelope)
      end

      count = create_rev_tiles(rev, diff_bbox)
      @@log.debug "    Created #{count} tile(s)"

      @prev['geom_obj'] = nil if @prev
      @prev = rev

      # GC has problems if we don't do this explicitly...
      #@prev['geom_obj'] = nil
    end

    @@log.debug "Done"
  end

  private

  def create_rev_tiles(rev, diff_bbox)
    return -1 if has_tiles(rev)

    count = 0
    geom = rev['geom_obj']
    geom_prep = rev['geom_obj'].to_prepared
    bbox = box2d_to_bbox(rev['bbox'])
    tile_count = bbox_tile_count(@zoom, bbox)
    diff_tile_count = bbox_tile_count(@zoom, diff_bbox) if diff_bbox

    @@log.debug "    tile_count = #{tile_count}, diff_tile_count = #{diff_tile_count}"

    if diff_tile_count and (diff_tile_count < 0.5 * tile_count)
      bounds = bbox_bound_tiles(@zoom, diff_bbox)
      tiles = bbox_to_tiles(@zoom, diff_bbox)
      count = @conn.exec("INSERT INTO way_tiles
        SELECT way_id, version, #{rev['rev']}, changeset_id, tstamp, x, y, geom
        FROM way_tiles WHERE way_id = #{rev['way_id']} AND version = #{rev['version']} AND
          rev = #{rev['rev'].to_i - 1} AND NOT (x >= #{bounds[0][0]} AND x <= #{bounds[1][0]} AND
          y >= #{bounds[0][1]} AND y <= #{bounds[1][1]})").cmd_tuples
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
        insert_tile(rev, x, y, intersection)
        count += 1
      end

      if index % 1000 == 0
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
    @conn.exec_prepared('has_tiles', [rev['way_id'], rev['version'], rev['rev']]).getvalue(0, 0).to_i > 0
  end

  def ensure_way_revisions(way_id)
    @conn.exec("SELECT OWL_CreateWayRevisions(#{way_id})")
  end

  def setup_prepared_statements
    @conn.prepare('select_revisions',
      "SELECT q.*, q.line::box2d AS bbox,
        CASE
          WHEN GeometryType(ST_MakeValid(q.line)) = 'LINESTRING' AND ST_IsClosed(q.line) AND ST_IsSimple(q.line)
            AND ST_IsValid(q.line)
          THEN  ST_ForceRHR(ST_MakePolygon(q.line))
          ELSE q.line
        END AS geom
      FROM (
        SELECT
          OWL_MakeLine(w.nodes, rev.tstamp) AS line,
          rev.*
        FROM way_revisions rev
        INNER JOIN ways w ON (w.id = rev.way_id AND w.version = rev.version)
        WHERE way_id = $1) q
      ORDER BY q.way_id, q.rev")

    @conn.prepare('has_tiles', "SELECT COUNT(*) FROM way_tiles WHERE way_id = $1 AND version = $2 AND rev = $3")

    @conn.prepare('insert_way_tile',
      "INSERT INTO way_tiles (way_id, version, rev, tstamp, changeset_id, x, y, geom) VALUES
        ($1, $2, $3, $4, $5, $6, $7, $8)")
  end
end

end
