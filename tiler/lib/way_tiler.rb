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
    for rev in @conn.exec_prepared('select_revisions', [way_id, changeset_id]).to_a
      next if !rev['geom']
      rev['geom_obj'] = @wkb_reader.read_hex(rev['geom'])
      @@log.debug "Way #{way_id} version #{rev['way_version']} rev #{rev['revision']}"

      create_rev_tiles(rev)

      # GC has problems if we don't do this explicitly...
      rev['geom_obj'] = nil
    end
  end

  private

  def create_rev_tiles(rev)
    geom = rev['geom_obj']
    geom_prep = rev['geom_obj'].to_prepared
    bbox = box2d_to_bbox(rev['bbox'])
    tile_count = bbox_tile_count(@zoom, bbox)

    @@log.debug "  tile_count = #{tile_count}"

    if tile_count < 64
      # Does not make sense to try to reduce small geoms.
      tiles = bbox_to_tiles(@zoom, bbox)
    else
      tiles_to_check = (tile_count < 2048 ? bbox_to_tiles(14, bbox) : prepare_tiles_to_check(geom_prep, bbox, 14))
      @@log.debug "  tiles_to_check = #{tiles_to_check.size}"
      tiles = prepare_tiles(tiles_to_check, geom_prep, 14, @zoom)
    end

    @@log.debug "  Processing #{tiles.size} tile(s)..."

    count = 0
    for tile in tiles
      x, y = tile[0], tile[1]
      tile_geom = get_tile_geom(x, y, @zoom)

      if geom_prep.intersects?(tile_geom)
        intersection = geom.intersection(tile_geom)
        intersection.srid = 4326
        insert_tile(rev, x, y, intersection)
        count += 1
      end
    end
    count
  end

  def insert_tile(rev, x, y, geom)
    @conn.exec_prepared('insert_way_tile', [rev['way_id'], rev['way_version'], rev['revision'], rev['tstamp'],
      rev['changeset_id'], x, y, @wkb_writer.write_hex(geom)])
  end

  def setup_prepared_statements
    @conn.prepare('select_revisions',
      "SELECT *, OWL_MakeLine(w.nodes, rev.tstamp) AS geom, OWL_MakeLine(w.nodes, rev.tstamp)::box2d AS bbox
      FROM way_revisions rev
      INNER JOIN ways w ON (w.id = rev.way_id AND w.version = rev.way_version)
      WHERE way_id = $1 AND ($2::int IS NULL OR rev.changeset_id = $2::int)")

    @conn.prepare('insert_way_tile',
      "INSERT INTO tiles (el_type, el_id, el_version, el_rev, tstamp, changeset_id, x, y, geom) VALUES
        ('W', $1, $2, $3, $4, $5, $6, $7, $8)")
  end
end

end
