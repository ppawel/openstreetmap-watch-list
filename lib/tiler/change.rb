require 'ffi-geos'
require 'time'

class Change
  attr_accessor :id
  attr_accessor :changeset_id
  attr_accessor :tstamp
  attr_accessor :el_type
  attr_accessor :el_id
  attr_accessor :el_version
  attr_accessor :action
  attr_accessor :geom
  attr_accessor :prev_geom
  attr_accessor :tags
  attr_accessor :prev_tags
  attr_accessor :nodes
  attr_accessor :prev_nodes

  def self.from_pg_array(changes)
    result = []
    for change_str in convert_array(changes) do
      result << Change.from_string(change_str)
    end
    result
  end

  def self.from_string(str)
    change = Change.new
    a = str.delete('(').delete(')').split(',')
    change.id = a[0].to_i
    change.tstamp = Time.parse(a[1])
    change.el_type = a[2]
    change.action = a[3]
    change.el_id = a[4].to_i
    change.el_version = a[5].to_i
    #p eval(str.gsub(/""/, '"').gsub(/^(.*?)"""/, '{').gsub(/"([^"]*)$/, '}'))
    #hash['geom_geojson'] = geojson(a[-2]) unless a[-2].empty?
    #hash['prev_geom_geojson'] = geojson(a[-1]) unless a[-1].empty?
    change
  end

  def ssinitialize(changeset_id, hash)
    @id = hash['id'].to_i
    @changeset_id = changeset_id
    @tstamp = Time.parse(hash['tstamp'])
    @el_type = hash['el_type']
    @el_id = hash['el_id'].to_i
    @el_version = hash['el_version'].to_i
    @el_action = hash['el_action']
    @tags = eval("{#{hash['tags']}}")
    @prev_tags = eval("{#{hash['prev_tags']}}") if hash['prev_tags']
    @geom = JSON[hash['geom']] if hash['geom']
    @prev_geom = JSON[hash['prev_geom']] if hash['prev_geom']
  end

  def as_json(options = {})
    Hash[instance_variables.collect {|key| [key.to_s.gsub('@', ''), instance_variable_get(key)]}]
  end

  #
  # Parse a PostgreSQL-Array output and convert into ruby array. This
  # does the real parsing work.
  #
  def self.convert_array(str)
      array_nesting = 0 # nesting level of the array
      in_string = false # currently inside a quoted string ?
      escaped = false # if the character is escaped
      sbuffer = '' # buffer for the current element
      result_array = ::Array.new # the resulting Array

      str.each_byte { |char| # parse character by character
          char = char.chr # we need the Character, not it's Integer

          if escaped then # if this character is escaped, just add it to the buffer
              sbuffer += char
              escaped = false
              next
          end

          case char # let's see what kind of character we have
              #------------- {: beginning of an array ----#
          when '{'
              if in_string then # ignore inside a string
                  sbuffer += char
                  next
              end

          if array_nesting >= 1 then # if it's an nested array, defer for recursion
              sbuffer += char
          end
          array_nesting += 1 # inside another array

          #------------- ": string deliminator --------#
          when '"'
              in_string = !in_string

              #------------- \: escape character, next is regular character #
          when "\\" # single \, must be extra escaped in Ruby
              if array_nesting > 1
                  sbuffer += char
              else
                  escaped = true
              end

              #------------- ,: element separator ---------#
          when ','
              if in_string or array_nesting > 1 then # don't care if inside string or
                  sbuffer += char # nested array
              else
                  if !sbuffer.is_a? ::Array then
                      #sbuffer = @base_type.parse(sbuffer)
                      #sbuffer = 'bla'
                  end
                  result_array << sbuffer # otherwise, here ends an element
                  sbuffer = ''
              end

          #------------- }: End of Array --------------#
          when '}'
              if in_string then # ignore if inside quoted string
                  sbuffer += char
                  next
              end

              array_nesting -=1 # decrease nesting level

              if array_nesting == 1 # must be the end of a nested array
                  sbuffer += char
                  sbuffer = convert_array( sbuffer ) # recurse, using the whole nested array
              elsif array_nesting > 1 # inside nested array, keep it for later
                  sbuffer += char
              else # array_nesting = 0, must be the last }
                  if !sbuffer.is_a? ::Array then
                      #sbuffer = @base_type.parse( sbuffer )
                      #sbuffer = 'ble'
                  end

                  result_array << sbuffer unless sbuffer.nil? # upto here was the last element
              end

              #------------- all other characters ---------#
          else
              sbuffer += char # simply append
          end
      }
      return result_array
  end # convert_array()
end
