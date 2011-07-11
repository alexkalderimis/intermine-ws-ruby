$LOAD_PATH << File.expand_path( File.dirname(__FILE__) + '/../lib' )
require "intermine/service"

service = Service.new("http://squirrel.flymine.org/intermine-test/service")

p service.version
p service.model.name

q = service.new_query("Employee")
q.add_views("name", "age")

p q.to_xml.to_s

sum = 0
q.each_row do |emp|
    puts emp
    sum += emp["age"]
end

total = q.results_size
puts "Average: #{sum/total} - #{total} employees"
