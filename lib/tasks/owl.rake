Rake::TestTask.new do |t|
  t.name = 'owl:test:tiler:realdata'
  t.loader = :testrb
  t.libs << 'lib/tiler'
  t.test_files = FileList['lib/tiler/test/tiler_realdata_test.rb']
  t.verbose = true
end

Rake::TestTask.new do |t|
  t.name = 'owl:test:tiler:unit'
  t.loader = :testrb
  t.libs << 'lib/tiler'
  t.test_files = FileList['lib/tiler/test/tiler_unit_test.rb']
  t.verbose = true
end

Rake::TestTask.new do |t|
  t.name = 'owl:test:api'
  #t.loader = :testrb
  t.libs << 'test'
  t.test_files = FileList['test/controllers/*.rb']
  t.verbose = true
end

# Don't need those, database is managed manually.

Rake.application.remove_task 'db:test:load'
Rake.application.remove_task 'db:test:purge'

namespace :db do
 namespace :test do 
   task :load do |t|
     # rewrite the task to not do anything you don't want
   end
   task :purge do |t|
      # rewrite the task to not do anything you don't want
   end  
  end
end