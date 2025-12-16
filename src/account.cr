require "./singleton"
require "./config"
require "./person"
require "./supcurses"

module Redwood

# `Account` contains the information about a single email ccount.
# It includes SMTP server information, and also the SMTP2GO API key if
# the SMTP2GO service is used instead of normal SMTP. The `Account`
# constructor extracts this information from the `Config` object, which
# is in turn derived from the file `~/.csup/config.yaml`.
#
# `Account` also includes `sendmail` and `gpgkey` properties,
# for compatibility with `sup`, but `csup` does not use these
# currently, and will probably never use them.
class Account < Person
  property sendmail : String
  property signature : String
  property gpgkey : String
  property smtp_server : String
  property smtp_port : Int32
  property smtp_user : String
  property smtp_password : String
  property reply_to : String
  property smtp2go_api_key : String

  # Return a value from an account config hash as a string, or
  # the empty string if the value isn't present.
  def cfg_string(h : Config::Account, name : String)
    if h[name]?
      h[name].as(String)
    else
      ""
    end
  end

  # Initializes an `Account` object with information from a `Config::Account` object.
  def initialize(h : Config::Account)
    raise ArgumentError.new("no name for account") unless h["name"]?
    raise ArgumentError.new("no email for account") unless h["email"]?
    super h["name"], h["email"]
    @sendmail = cfg_string(h, "sendmail")	# not used, but here for Sup compatibility
    @signature = cfg_string(h, "signature")
    @gpgkey = cfg_string(h, "gpgkey")		# not used, but here for Sup compatibility
    @smtp_server = cfg_string(h, "smtp_server")
    if h["smtp_port"]?
      @smtp_port = h["smtp_port"].as(String).to_i
    else
      @smtp_port = 0
    end
    @smtp_user = cfg_string(h, "smtp_user")
    @smtp_password = cfg_string(h, "smtp_password")
    @reply_to = cfg_string(h, "reply_to")
    @smtp2go_api_key = cfg_string(h, "smtp2go_api_key")
  end

end

# `Account_Manager` is a singleton class that stores information about all email accounts
# described in the file `~/.csup/config.yaml`.
class AccountManager
  singleton_class

  property default_account : Account?
  @email_map = Hash(String, Account).new
  @accounts = Hash(Account, Bool).new
  @default_account : Account?

  # Creates a list of all accounts described in the file `~/.csup/config.yaml`.
  # It creates information for the "default" account first, then all of
  # other accounts (if any).
  def initialize(accounts : Config::Accounts)
    singleton_pre_init
    @default_account = nil

    add_account accounts["default"], true
    accounts.each { |k, v| add_account(v, false) unless k == "default" }
    singleton_post_init
  end

  # Returns a list of all email addresses that have associated `Account` objects.
  def user_emails : Array(String)
    @email_map.keys
  end
  singleton_method user_emails

  # Adds a new email account to the account list.  It must be called first with the
  # default account. For subsequent accounts, it fills in missing (optional) values from the
  # default account.  These optional values are `name`, `sendmail`, `signature`,
  # and `gpgkey`. `sendmail` and `gpgkey` are not used in csup, but are present
  # for compatibility with sup.  An email account can have several alternative
  # email address, so `add_account` maintains a hash (`email_map`) that maps
  # an email address to its associated `Account` object.
  def add_account(hash : Config::Account, default=false)
    raise ArgumentError.new("no email specified for account") unless hash["email"]
    unless default
      {% for k in ["name", "sendmail", "signature", "gpgkey"] %}
	a = @default_account
	if a
	  v = a.{{k.id}}
	  if v
	    hash[{{k}}] ||= v
	  end
	end
      {% end %}
      #[:name, :sendmail, :signature, :gpgkey].each { |k| hash[k] ||= @default_account.send(k) }
    end

    hash["alternates"] ||= [] of String
    #fail "alternative emails are not an array: #{hash[:alternates]}" unless hash[:alternates].kind_of? Array

    #[:name, :signature].each { |x| hash[x] ? hash[x].fix_encoding! : nil }

    a = Account.new hash
    @accounts[a] = true

    if default
      raise ArgumentError.new("multiple default accounts") if @default_account
      @default_account = a
    end

    ([hash["email"].as(String)] + hash["alternates"].as(Array(String))).each do |email|
      #system("echo adding #{email} to email_map >>/tmp/csup.log")
      next if @email_map.member? email
      @email_map[email] = a
    end

    #hash[:regexen].each do |re|
    #  @regexen[Regexp.new(re)] = a
    #end if hash[:regexen]
  end

  # Checks if there is an `Account` for the specified `Person`.
  def is_account?(p : Person) : Bool
    is_account_email?(p.email)
  end
  singleton_method is_account?, p

  # Checks if there is an `Account` for the specified email address.
  def is_account_email?(email : String) : Bool
    !account_for(email).nil?
  end
  singleton_method is_account_email?, email

  # Returns the `Account` for the specified email address, or nil
  # if there is no such `Account`.
  def account_for(email : String) : Account?
    if @email_map.has_key?(email)
      @email_map[email]
    else
      nil
    end
    #if(a = @email_map[email])
    #  a
    #else
    #  @regexen.argfind { |re, a| re =~ email && a }
    #end
  end
  singleton_method account_for, email

  # Returns the full email address (including the name)
  # for the specified email address.
  def full_address_for(email : String) : String?
    a = account_for(email)
    if a
      return Person.full_address a.name, email
    else
      return nil
    end
  end
  singleton_method full_address_for, email

  singleton_method default_account

end	# AccountManager

end	# Redwood
