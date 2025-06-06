#!/usr/bin/env ruby

def version
  if File.exist?('.fslckout')
    p = IO::popen(['fossil', 'info'])
    p.each do |line|
      if line =~ /^checkout:\s*(..........).*$/
	return "fossil-" + $1
      end
    end
    return "unknown"
  else
    p = IO::popen(['git', 'rev-parse', 'HEAD'])
    return "git-" + p.read[0, 7]
  end
  p.close
end

def iso_date
  Time.now.strftime("%Y-%m-%d")
end

File.open("version.cr", "w") do |f|
  f.puts "module Redwood"
  f.puts "VERSION = \"#{iso_date} #{version}\""
  f.puts "end"
end
