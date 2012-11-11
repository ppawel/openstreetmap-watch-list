require 'optparse'

module Tiler

def self.parse_cmdline_options
  options = {}

  opt = OptionParser.new do |opts|
    opts.banner = "Usage: owl_tiler.rb [options]"

    opts.separator('')

    opts.on("--zoom-level z", "Zoom level for which to generate geometry tiles (optional, default is 16)") do |z|
      options[:zoom_level] = z.to_i
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
    opts.on("--retile", "Remove existing tiles and regenerate tiles from scratch (optional, default is false)") do |o|
      options[:retile] = o
    end
  end

  opt.parse!

  options[:changesets] ||= ['all']
  options[:zoom_level] ||= 16

  options
end

end
