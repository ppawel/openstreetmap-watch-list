require 'logger'

module Tiler
module Logger
  class <<self
    attr_accessor :log
  end

  @@log = ::Logger.new(STDOUT)
  @@log.level = ::Logger::DEBUG
  self.log = @@log
end
end
