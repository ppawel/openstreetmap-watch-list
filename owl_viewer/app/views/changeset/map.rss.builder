xml.instruct! :xml, :version => "1.0"
xml.rss :version => "2.0" do
  xml.channel do
    xml.title "OpenStreetMap Changesets"

    @changesets.each do |changeset|
      xml.item do
    xml.title "Changeset #{changeset.id} by #{changeset.user.name}"
  description = "<p>Changeset <a href=\"http://www.openstreetmap.org/browse/changeset/#{changeset.id}\">#{changeset.id}</a> by <a href=\"http://www.openstreetmap.org/user/#{changeset.user.name}\">#{changeset.user.name}</a>"
  xml.description { xml.cdata! description }
  xml.pubDate changeset.created_at.to_s(:rfc822)
      end
    end
  end
end
