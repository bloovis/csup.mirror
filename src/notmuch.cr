require "json"
require "./pipe"
require "./hook"
require "./contact"
require "./account"
require "./logger"

module Redwood

# `Notmuch` is a module (effectively, a singleton class) that provides
# the interface to the Notmuch mailstore.  It includes methods for
# searching and tagging messages, extracting messages parts,
# and polling for new messages.
module Notmuch
  class ParseError < Exception
  end

  COMPL_OPERATORS = %w(and or not)

  # Completion prefixes for the search command, i.e., the reserved
  # words in the Notmuch query language, plus the boolean operators
  COMPL_PREFIXES =
    %w(
      body from to subject attachment mimetype tag id thread path folder
      date lastmod
      is has label filename filetype before on in during after
    ).map{|p|p+":"} + COMPL_OPERATORS

  extend self

  # Low-level methods.

  # Returns the lastmod counter (the counter for number of database updates).
  # Use this to determine if the mailstore has changed since the last call
  # to `lastmod`.
  def lastmod : Int32
    Pipe.run("notmuch", ["count", "--lastmod"]).split.last.to_i
  end

  # Polls for new messages added to the mailstore.
  def poll
    Pipe.run("notmuch", ["new", "--quiet"], check_stderr: false)
  end

  # Returns the number of messages in the mailstore that match the *query*.
  # If query is the empty string (the default), returns the number
  # of all messages in the mailstore.
  def count(query : String = "")
    Pipe.run("notmuch", ["count", query]).to_i
  end

  # Performs a search and returns the output as an array of lines.
  # See `man notmuch-search` for details.
  # Arguments:
  # * *query*: the query string.
  # * *format*: specifies the desired output format: "json" or "text" (default).
  # * *exclude*: true if deleted or spam messages should be excluded
  #   from the results (default false).
  # * *output*: specifies the kind of output: "threads" (default), "files", or "messages".
  # * *offset*: the number of results to skip (default 0).
  # * *limit*: the maximum number of results to return (default unlimited).
  # is true
  def search(query : String,
	     format : String = "text",
	     exclude : Bool = true,
	     output : String = "threads",
	     offset : (Int32 | Nil) = nil,
	     limit : (Int32 | Nil) = nil) : Array(String)
    args = ["search", "--format=#{format}", "--output=#{output}"]
    args << "--offset=#{offset}" if offset
    args << "--limit=#{limit}" if limit
    args << "--exclude=false" unless exclude
    args << query
    #STDERR.puts "notmuch #{args}"
    debug "notmuch #{args}"
    Pipe.run("notmuch", args).lines
  end

  # Returns the JSON representation for the messages matching a query.  See
  # `man notmuch-show` for details. Arguments:
  # * *query*: the search query; this is typically a list of thread IDs but can
  #   include other queries.
  # * *body*: true if the bodies of the messages should be included in
  #   the results (default false).
  # * *html*: true if "text/html" message parts should be included in
  #   the results (default false).
  def show(query : String,
	   body : Bool = false,
	   html : Bool = false) : JSON::Any
    JSON.parse(Pipe.run("notmuch",
			["show", "--format=json", "--include-html=#{html}",
                         "--body=#{body}", "--exclude=#{!body}", query],
			check_stderr: false))
  end

  # Sets the tags for one or more messages, removing any pre-existing tags
  # for those messages.  See `man notmuch-tag` for details.
  # *query_tags* is an array of tuples, each of which is in this form:
  # * a query string in the form "id:messageid"
  # * an array of tags to apply to that message
  def tag_batch(query_tags : Array({String, Array(String)}))
    return if query_tags.empty?
    input = query_tags.map do |q, ls|
      "#{ls.map{|l| "+#{l} "}.join} -- #{q}\n"
    end.join
    # @@logger.debug("tag input: #{input}") if @@logger
    #STDERR.puts "notmuch tag --remove-all --batch, input:\n#{input}\n"
    Pipe.run("notmuch", ["tag", "--remove-all", "--batch"], input: input, check_stderr: false)
  end

  # Saves a message part to a file.  Arguments:
  # * *msgid*: the message ID
  # * *partid*: the part ID
  # * *filename*: name of the output file
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

  # Writes a message part to a pipe, and yields the pipe to
  # the passed-in block.  The block should do an `IO#copy` to save the
  # message part. This is used to attach a file to an `EMail::Message`.
  # Arguments:
  # * *msgid*: the message ID
  # * *partid*: the part ID
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

  # Extracts a message part and passes it to the `mime-view` hook.  Returns
  # true if the hook was run successfully.
  #
  # The `mime-view` hook (a script that lives in `~/.csup/hooks`) will
  # receive a line containing the MIME content type, followed by the raw
  # data of the message part.  The hook can choose to display the data
  # in an external program, or it can ignore the data.  Arguments:
  # * *msgid*: the message ID
  # * *partid*: the part ID
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

  # High-level methods.

  # Returns a list of filenames corresponding to the message whose ID is *mid*.
  def filenames_from_message_id(mid : String) : Array(String)
    search("id:#{mid}", exclude: false, format: "text", output: "files", limit: 1)
  end

  # Returns the thread ID for message whose ID is *mid*, or the empty string if not found.
  def thread_id_from_message_id(mid : String) : String
    lines = search("id:#{mid}", exclude: false, format: "text", output: "threads", limit: 1)
    if lines.size > 0
      return lines[0]
    else
      return ""
    end
  end

  # Returns the list of tags for the message whose ID is *mid*.
  def tags_from_message_id(mid : String) : Array(String)
    search("id:#{mid}", exclude: false, output: "tags")
  end

  # Searches notmuch for a list of all possible email addresses.  This turns out to be
  # too expensive for any non-trivial mailstore, so just return an empty list.
  def load_contacts(email_addresses : Array(String), limit : Int32 = 20)
    return Array(Person).new
  end

  # Translates a query string from the user into one that can
  # be passed to `notmuch search`.  This is used to provide compatibility
  # with the query language used in sup.  Translations include:
  # * to:/from:person -> look up person's email address contacts list
  # * label:/is:/has: -> tag:
  # * filename: -> attachment:
  # * filetype: -> mimetype:
  # * before|on|in|during|after: -> date:?..?
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

  # Runs `notmuch insert` to store a message in the
  # folder named *folder* (which can be nil).  The caller supplies a block that takes
  # an `IO` object; the block should write the message contents
  # to the IO.  Returns true if successful, or false otherwise.
  # This is used to save drafts or sent messages to the mailstore.
  def insert(folder, &block : IO -> _) : Bool
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

  # Runs `notmuch search --output=tags '*'` to get a list of all tags
  # for all messages, and returns the list as an array of strings.
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
