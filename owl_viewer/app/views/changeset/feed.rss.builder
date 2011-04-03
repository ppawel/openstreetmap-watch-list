xml.instruct! :xml, :version => "1.0"
xml.rss :version => "2.0" do
  xml.channel do
    range_str = @ranges.collect {|r| r.join("-") }.join(",")
    xml.title "List of changes (#{range_str})"
    xml.link "http://matt.dev.openstreetmap.org/owl_viewer"
    xml.description "Changes for range #{range_str}"

    @changesets.each do |id,time,n|
      xml.item do
      	details = @cs2details[id]
      	if details.nil? 
	  user_name = "unknown"
	  xml.title "Changeset #{id}"
	else
	  user_name = details[0] 
	  xml.title "Changeset #{id} by #{user_name}"
	end
	description = "<p>By <a href=\"http://www.openstreetmap.org/user/#{user_name}\">#{user_name}</a> covering #{n} tiles"
	description += ", with comment \"#{details[1]}\"" unless details.nil? or details[1].nil?
	description += ", using \"#{details[2]}\"" unless details.nil? or details[2].nil?
	description += ", and tagged as a bot" unless details.nil? or details[3].nil? or details[3] != "t"
	description += ". View changeset on <a href=\"http://www.openstreetmap.org/browse/changeset/#{id}\">main OSM site</a>.</p>"
	xml.description { xml.cdata! description }
	xml.pubDate time.to_s(:rfc822)
        xml.link "http://matt.dev.openstreetmap.org/owl_viewer/tiles/#{id}"
        xml.guid "http://matt.dev.openstreetmap.org/owl_viewer/tiles/#{id}"
      end
    end
  end
end
