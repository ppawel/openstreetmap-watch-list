atom_feed do |feed|
  feed.title("OpenStreetMap Changesets")
  #feed.updated(@changesets[0].created_at) if @changesets.length > 0

  @changesets.each do |changeset|
    feed.entry(changeset, :url => "http://www.openstreetmap.org/browse/changeset/#{changeset.id}") do |entry|
      entry.title("Changeset #{changeset.id} by #{changeset.user_name}")
      entry.content("Changes: #{changeset.entity_changes}", :type => 'html')

      entry.author do |author|
        author.name(changeset.user_name)
      end
    end
  end
end
