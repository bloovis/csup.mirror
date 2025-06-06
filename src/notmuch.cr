require "json"
require "./pipe"
require "./hook"
require "./contact"
require "./account"
require "./logger"

module Redwood

module Notmuch
  class ParseError < Exception
  end

  # Completion prefixes for search command.
  COMPL_OPERATORS = %w(and or not)
  COMPL_PREFIXES =
    %w(
      body from to subject attachment mimetype tag id thread path folder
      date lastmod
      is has label filename filetype before on in during after
    ).map{|p|p+":"} + COMPL_OPERATORS

  extend self

  # low-level

  def lastmod : Int32
    Pipe.run("notmuch", ["count", "--lastmod"]).split.last.to_i
  end

  def poll
    Pipe.run("notmuch", ["new", "--quiet"], check_stderr: false)
  end

  def count(query : String = "")
    Pipe.run("notmuch", ["count", query]).to_i
  end

  def search(query : String,
	     format : String = "text",
	     exclude : Bool = true,
	     output : String = "threads",
	     offset : (Int32 | Nil) = nil,
	     limit : (Int32 | Nil) = nil) : Array(String)
    # search threads, return thread ids
    args = ["search", "--format=#{format}", "--output=#{output}"]
    args << "--offset=#{offset}" if offset
    args << "--limit=#{limit}" if limit
    args << "--exclude=false" unless exclude
    args << query
    #STDERR.puts "notmuch #{args}"
    debug "notmuch #{args}"
    Pipe.run("notmuch", args).lines
  end

  def show(query : String,
	   body : Bool = false,
	   html : Bool = false) : JSON::Any
    JSON.parse(Pipe.run("notmuch",
			["show", "--format=json", "--include-html=#{html}",
                         "--body=#{body}", "--exclude=#{!body}", query],
			check_stderr: false))
  end

  def tag(query : String)
    Pipe.run("notmuch", ["tag", query])
  end

  # Each entry in query_tags is a tuple containing:
  # - a query string in the form "id:messageid"
  # - an array of tags to apply to that message
  def tag_batch(query_tags : Array({String, Array(String)}))
    return if query_tags.empty?
    input = query_tags.map do |q, ls|
      "#{ls.map{|l| "+#{l} "}.join} -- #{q}\n"
    end.join
    # @@logger.debug("tag input: #{input}") if @@logger
    #STDERR.puts "notmuch tag --remove-all --batch, input:\n#{input}\n"
    Pipe.run("notmuch", ["tag", "--remove-all", "--batch"], input: input, check_stderr: false)
  end

  # Save a message part to a file.
  def save_part(msgid : String, partid : Int32, filename : String) : Bool
    if File.exists?(filename)
      unless BufferManager.ask_yes_or_no "File \"#{filename}\" exists. Overwrite?"
        info "Not overwriting #{filename}"
        return false
      end
    end

    #STDERR.puts "About to run notmuch show --part=#{partid} id:#{msgid}"
    begin
      pipe = Pipe.new("notmuch", ["show", "--part=#{partid}", "id:#{msgid}"])
      pipe.start do |p|
	p.receive do |output|
	  File.open(filename, "w") do |f|
	    IO.copy(output, f)
	  end
	end
      end
    rescue e
      BufferManager.flash e.message || "Unknown error saving #[filename}"
      return false
    end
    return true
  end

  # Read the specified message part into a pipe, and yield the pipe to
  # the passed-in block.  The block should do an IO.copy to save the
  # message part. This will be used to attach a file to an EMail::Message.
  def write_part(msgid : String, partid : Int32) : Bool
    #STDERR.puts "About to run notmuch show --part=#{partid} id:#{msgid}"
    pipe = Pipe.new("notmuch", ["show", "--part=#{partid}", "id:#{msgid}"])
    pipe.start do |p|
      p.receive do |output|
	yield output
      end
    end
    return true
  end

  def view_part(msgid : String, partid : Int32, content_type : String) : Bool
    #STDERR.puts "view_part: notmuch show --part=#{partid}  id:#{msgid}"
    pipe = Pipe.new("notmuch", ["show", "--part=#{partid}", "id:#{msgid}"])
    success = false
    pipe.start do |p|
      p.receive do |output|
        #STDERR.puts "view_part: running mime-view hook, content type #{content_type}"
        success = HookManager.run("mime-view") do |hook|
	  hook.transmit do |f|
	    f.puts content_type
	    IO.copy(output, f)
	  end
	end
      end
    end
    return success
  end

  # high-level

  def filenames_from_message_id(mid : String)
    search("id:#{mid}", exclude: false, format: "text", output: "files", limit: 1)
  end

  # Return thread id for the given message id, or empty string if not found.
  def thread_id_from_message_id(mid : String) : String
    lines = search("id:#{mid}", exclude: false, format: "text", output: "threads", limit: 1)
    if lines.size > 0
      return lines[0]
    else
      return ""
    end
  end

  def tags_from_message_id(mid : String)
    search("id:#{mid}", exclude: false, output: "tags")
  end

  # It's too expensive to search notmuch for addresses, so just return an empty list.
  def load_contacts(email_addresses : Array(String), limit : Int32 = 20)
    return Array(Person).new
  end

  # Translate a query string from the user into one that can
  # be passed to notmuch search.  Translations include:
  # - to:/from:person -> look up person's email address contacts list
  # - label:/is:/has: -> tag:
  # - filename: -> attachment:
  # - filetype: -> mimetype:
  # - before|on|in|during|after: -> date:?..?

  def translate_query(s : String) : String
    subs = ""

    begin
      subs = SearchManager.expand s
    rescue e : SearchManager::ExpansionError
      raise ParseError.new(e.message)
    end
    subs = subs.gsub(/\b(to|from):(\S+)\b/) do
      field, value = $1, $2
      p = ContactManager.contact_for(value)
      if p
        "#{field}:#{p.email}"
      elsif value == "me"
        "(" + AccountManager.user_emails.map { |e| "#{field}:#{e}" }.join(" OR ") + ")"
      else
        "#{field}:#{value}"
      end
    end

    ## gmail style "is" operator
    subs = subs.gsub(/\b(is|has):(\S+)\b/) do
      field, label = $1, $2
      case label
      when "read"
        "(not tag:unread)"
      when "spam"
        "tag:spam"
      when "deleted"
        "tag:deleted"
      else
        "tag:#{$2}"
      end
    end

    ## labels are stored lower-case in the index
    subs = subs.gsub(/\blabel:([\w-]+)\b/) do
      label = $1
      "tag:#{label.downcase}"
    end
    subs = subs.gsub(/\B-(tag|label):([\w-]+)/) do
      label = $2
      "(not tag:#{label.downcase})"
    end

    ## gmail style attachments "filename" and "filetype" searches
    subs = subs.gsub(/\b(filename|filetype):(\((.+?)\)\B|(\S+)\b)/) do
      field, name = $1, ($3? || $2)
      case field
      when "filename"
        #debug "filename: translated #{field}:#{name} to attachment:\"#{name.downcase}\""
        "attachment:\"#{name.downcase}\""
      when "filetype"
        #debug "filetype: translated #{field}:#{name} to mimetype:#{name.downcase}"
        "mimetype:#{name.downcase}"
      end
    end

    subs = subs.gsub(/\b(before|on|in|during|after):(\((.+?)\)\B|(\S+)\b)/) do
      field, datestr = $1, ($3? || $2)
      datestr = datestr.gsub(" ","_")       # translate spaces to underscores
      case field
      when "after"
	"date:#{datestr}.."
      when "before"
	"date:..#{datestr}"
      else
	"date:#{datestr}"
      end
    end

    # If the user didnt't explicitly request spam, deleted, or killed tags,
    # filter out messages with those tags.
    #%w(spam deleted killed).each do |tag|
    #   subs += " (not tag:#{tag})" if !subs.includes?("tag:#{tag}")
    #end

    #debug "translated query: #{subs.inspect}"
    return subs
  end

  # Run "notmuch insert" to store a message in the specified
  # folder (which can be nil).  Supply a block that takes
  # an IO object; the block should write the message contents
  # to the IO.  Return true if successful, or false otherwise.

  def insert(folder, &block : IO -> _) : Bool	# supply a block that takes an IO
    cmd = "notmuch"
    args = ["insert"]
    if folder
      args << "--create-folder"
      args << "--folder=#{folder}"
    end
    pipe = Pipe.new(cmd, args)
    unless pipe.success
      debug "Unable to run #{cmd} #{args.join(" ")}"
      return false
    end
    exit_status = pipe.start do |p|
      p.transmit do |f|
	block.call(f)
      end
    end
    if exit_status != 0
      debug "notmuch insert returned exit status #{exit_status}"
      return false
    end
    Redwood.poll
    return true
  end

  # Run "notmuch search --output=tags '*'" to get a list of all tags.

  def all_tags : Array(String)
    ret = [] of String
    cmd = "notmuch"
    args = ["search", "--output=tags", "*"]
    pipe = Pipe.new(cmd, args)
    unless pipe.success
      debug "Unable to run #{cmd} #{args.join(" ")}"
      return ret
    end
    exit_status = pipe.start do |p|
      p.receive do |f|
	f.each_line {|l| ret << l.chomp}
      end
    end
    if exit_status != 0
      debug "notmuch search returned exit status #{exit_status}"
    end
    return ret
  end

end	# module Notmuch

end	# module Redwood
