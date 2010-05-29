require 'rubygems'
require 'pg'
require 'xml/libxml'
require 'open-uri'

API_URL = "http://api.openstreetmap.org/api/0.6"

conn = PGconn.connect("dbname=owl")

cs_ids = conn.query("select id from changeset_details where not closed").collect { |r| r['id'].to_i }
puts "Updating changesets: #{cs_ids.inspect}"
cs_ids.each do |cs_id|
  doc = XML::Parser.string(open(API_URL + "/changeset/#{cs_id}", 
                                "User-Agent" => "OWL changeset details updater (Ruby/#{RUBY_VERSION})").read).parse
  cs = doc.find("/osm/changeset").first
  assoc = cs.children.select { |c| c.name == "tag" }.collect { |c| [c["k"].to_s, c["v"].to_s] }
  tags = assoc.inject(Hash.new) {|h,x| h[x[0]]=x[1]; h}
  
  comment = tags["comment"]
  created_by = tags["created_by"]
  closed = (cs["open"] == "false")
  bot = tags["bot"] && (tags["bot"]=="true" || tags["bot"]=="yes")
  
  query = "update changeset_details set "
  query += "closed=#{closed.inspect}"
  query += ", comment=E'#{conn.escape(comment)}'" unless comment.nil?
  query += ", created_by=E'#{conn.escape(created_by)}'" unless created_by.nil?
  query += ", bot_tag=#{bot.inspect}" unless bot.nil?
  query += " where id=#{cs_id}"
  conn.query(query)
  #puts query
end

