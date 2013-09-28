
Rake::TestTask.new do |t|
  t.name = 'owl:test'
  t.libs << 'lib/tiler'
  t.test_files = FileList['lib/tiler/test/changeset_tiler_test.rb']
  t.verbose = true
end
