require 'rubygems'
require 'fileutils'
require 'pg'

OUTPUT_FILE='/home/matt/public_html/dupe_nodes/leaderboard.html'
TMP_FILE='/tmp/leaderboard.html'
CONN_STRING='dbname=owl'

class UserInfoCache
  class Info
    def initialize(name, num_dupes)
      @name, @num_dupes = name, num_dupes
    end
    attr_accessor :name, :num_dupes
  end

  def initialize(con)
    @db_con = con
    @info = Hash.new
  end

  def name(uid)
    lookup(uid).name
  end

  def num_dupes(uid)
    lookup(uid).num_dupes
  end
  
  def lookup(uid)
    if @info.has_key? uid
      @info[uid]
    else
      res = @db_con.query("select name from users where id=#{uid.to_i}")
      name = res.ntuples > 0 ? res[0]['name'] : nil
      res2 = @db_con.query("select sum(num) as num from changesets where uid=#{uid.to_i} and id in (select id from tmp_cs)")
      num_dupes = res2.ntuples > 0 ? res2[0]['num'].to_i : 0
      info = Info.new(name, num_dupes)
      @info[uid] = info
      info
    end
  end
end

def mk_table(fh, con, ucache, desc, order, sign)
  fh.puts("<h3>Most duplicate nodes #{desc} over the past day</h3>")
  fh.puts("<table border=\"0\" margin=\"0\" padding=\"0\"><tr bgcolor=\"#aaaaaa\"><th>Changeset ID</th><th>User</th><th>Number #{desc}</th><th>View in OWL</th><th>Tiles covered</th><th>User total today</th></tr>")
  res = con.query("select id,uid,num from changesets where id in (select id from tmp_cs) order by num #{order} limit 10")
  even = true
  res.each do |row|
    cs_id = row['id'].to_i
    uid = row['uid'].to_i
    res2 = con.query("select count(distinct tile) as num from changes where changeset=#{cs_id}")
    color = even ? "eeeeee" : "dddddd"
    user = ucache.name(uid).nil? ? uid.to_s : "<a href=\"http://www.openstreetmap.org/user/#{ucache.name(uid)}\">#{ucache.name(uid)}</a>"
    fh.puts("<tr bgcolor=\"##{color}\"><td><a href=\"http://www.openstreetmap.org/browse/changeset/#{cs_id}\">#{cs_id}</a></td><td>#{user}</td><td>#{sign * row['num'].to_i}</td><td><a href=\"http://matt.dev.openstreetmap.org/owl_viewer/tiles/#{cs_id}\">view</a></td><td>#{res2[0]['num']}</td><td>#{ucache.num_dupes(uid) * sign}</td></tr>")
    even = !even
  end
  fh.puts("</table>")
end

con = PGconn.connect(CONN_STRING)

# setup temporary table, so we can re-use this (fairly) expensive query
con.query("create temporary table tmp_cs as select distinct changeset as id from changes where time > now() - '1 days'::interval")
con.query("create index tmp_cs_idx on tmp_cs(id)")
ucache = UserInfoCache.new(con)

File.open(TMP_FILE, 'w') do |fh|
  fh.puts('<html><body style="font-family: sans-serif;">')
  mk_table(fh, con, ucache, "cleared", "desc", 1)
  mk_table(fh, con, ucache, "created", "asc", -1)
  fh.puts('</body></html>')
end
FileUtils.mv(TMP_FILE, OUTPUT_FILE)
#FileUtils.rm(TMP_FILE)

