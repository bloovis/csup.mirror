require "../src/csup"
require "../src/person"

module Redwood

init_managers

def print_person(p : Person)
  puts "  to_s = '#{p.to_s}'"
  puts "  short_name = '#{p.shortname}'"
  puts "  mediumname = '#{p.mediumname}'"
  puts "  full_address = '#{p.full_address}'"
end

def test_new(name : String?, email : String)
  puts "Testing Person.new(name '#{name}', email '#{email}')"
  p = Person.new(name, email)
  print_person(p)
end

def test_address(address : String)
  puts "Testing Person.from_address('#{address}')"
  p = Person.from_address(address)
  print_person(p)
end

def test_list(s : String)
  puts "Testing Person.from_address_list('#{s}')"
  ps = Person.from_address_list(s)
  ps.each {|p| print_person(p)}
end

def test_from_name_and_email(name : String?, email : String)
  puts "Testing Person.from_name_and_email('#{name}', email '#{email}')"
  p = Person.from_name_and_email(name, email)
  print_person(p)
  puts "  name #{p.name}, alias #{ContactManager.alias_for(p)}, email #{p.email}"
end

test_new("Mark Alexander", "marka@pobox.com")
test_new(nil, "noname@pobox.com")
test_address("marka@pobox.com")
test_address("\"A real somebody!\" <somebody@pobox.com>")
test_list("marka@pobox.com, potus@whitehouse.gov")
test_from_name_and_email("Mark Alexander", "marka@pobox.com")

end	# Redwood
