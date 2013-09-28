require 'optparse'

module Tiler

def self.parse_cmdline_options
  options = {}

  opt = OptionParser.new do |opts|
    opts.banner = "Usage: tiler.rb [options]"

    opts.on("--changes", "Generate changes for each changeset before doing the tiling") do |o|
      options[:changes] = o
    end

    opts.separator('')

    opts.on("--retile", "Remove existing tiles and regenerate tiles from scratch (optional, default is false)") do |o|
      options[:retile] = o
    end
  end

  opt.parse!
  options
end

end
