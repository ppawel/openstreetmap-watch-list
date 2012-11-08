module Tiler

# Implements tiling logic for summary tiles.
class SummaryTiler
  include ::Tiler::Logger

  attr_accessor :conn

  def initialize(conn)
    @conn = conn
  end

  def generate_summary_tiles(summary_zoom)
    clear_summary_tiles(summary_zoom)
    subtiles_per_tile = 2**16 / 2**summary_zoom

    for x in (0..2**summary_zoom - 1)
      for y in (0..2**summary_zoom - 1)
        num_changesets = @conn.query("
          SELECT COUNT(DISTINCT changeset_id) AS num_changesets
          FROM changeset_tiles
          WHERE zoom = 16
            AND x >= #{x * subtiles_per_tile} AND x < #{(x + 1) * subtiles_per_tile}
            AND y >= #{y * subtiles_per_tile} AND y < #{(y + 1) * subtiles_per_tile}
          ").to_a[0]['num_changesets'].to_i

        @@log.debug "Tile (#{x}, #{y}), num_changesets = #{num_changesets}"

        @conn.query("INSERT INTO summary_tiles (num_changesets, zoom, x, y)
          VALUES (#{num_changesets}, #{summary_zoom}, #{x}, #{y})")
      end
    end
  end

  def clear_summary_tiles(zoom)
    @conn.query("DELETE FROM summary_tiles WHERE zoom = #{zoom}").cmd_tuples
  end
end
