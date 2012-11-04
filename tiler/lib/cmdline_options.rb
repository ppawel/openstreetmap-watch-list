require 'optparse'

module Tiler

def self.parse_cmdline_options
  options = {}

  opt = OptionParser.new do |opts|
    opts.banner = "Usage: owl_tiler.rb [options]"

    opts.separator('')
    opts.separator('Geometry tiles')
    opts.separator('')

    opts.on("--geometry-tiles x,y,z", Array, "Comma-separated list of zoom levels for which to generate geometry tiles") do |list|
      options[:geometry_tiles] = list.map(&:to_i)
    end

    opts.separator('')

    opts.on("--changesets x,y,z", Array,
        "List of changesets; possible values for this option:",
        "all - all changesets from the database",
        "id1,id2,id3 - list of specific changeset ids to process",
        "Default is 'all'.") do |c|
      options[:changesets] = c
    end

    opts.separator('')

    opts.on("--processing-tile-limit N", "Skip changesets with number of tiles to process larger than N") do |limit|
      options[:processing_tile_limit] = limit.to_i
    end

    opts.separator('')

    opts.on("--processing-change-limit N", "Skip changesets with number of changes larger than N") do |limit|
      options[:processing_change_limit] = limit.to_i
    end

    opts.separator('')
    opts.on("--retile", "Remove existing tiles and regenerate tiles from scratch (optional, default is false)") do |o|
      options[:retile] = o
    end

    opts.separator('')
    opts.separator('Summary tiles')
    opts.separator('')

    opts.on("--summary-tiles x,y,z", Array, "Comma-separated list of zoom levels for which to generate summary tiles") do |list|
      options[:summary_tiles] = list.map(&:to_i)
    end
  end

  opt.parse!

  if !options[:geometry_tiles] and !options[:summary_tiles]
    puts opt.help
    exit 1
  end

  options[:changesets] ||= ['all']
  options[:geometry_tiles] ||= []
  options[:processing_change_limit] ||= 11111
  options[:summary_tiles] ||= []

  options
end

end
