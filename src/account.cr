require "./singleton"
require "./config"
require "./person"
require "./supcurses"

module Redwood

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

  def initialize(h : Config::Account)
    raise ArgumentError.new("no name for account") unless h["name"]?
    raise ArgumentError.new("no email for account") unless h["email"]?
    super h["name"], h["email"]
    @sendmail = cfg_string(h, "sendmail")		# not used, but here for Sup compatibility
    @signature = cfg_string(h, "signature")
    @gpgkey = cfg_string(h, "gpgkey")
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

  # Default sendmail command for bouncing mail,
  # deduced from #sendmail
  def bounce_sendmail
    @sendmail.sub(/\s(\-(ti|it|t))\b/) do |match|
      case $1
      when "-t" then ""
      else " -i"
      end
    end
  end
end

class AccountManager
  singleton_class

  property default_account : Account?
  @email_map = Hash(String, Account).new
  @accounts = Hash(Account, Bool).new
  @default_account : Account?

  def initialize(accounts : Config::Accounts)
    singleton_pre_init
    #@email_map = Hash(String, Account)
    #@accounts = Hash(Account, Bool)
    #@regexen = {}
    @default_account = nil

    add_account accounts["default"], true
    accounts.each { |k, v| add_account(v, false) unless k == "default" }
    singleton_post_init
  end

  # This doesn't seem to be used anywhere.
#  def user_accounts : Array(Config::Account)
#    @accounts.keys
#  end
  
  def user_emails : Array(String)
    @email_map.keys # .select { |e| String === e }
  end
  singleton_method user_emails

  ## must be called first with the default account. fills in missing
  ## values from the default account.
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

  def is_account?(p : Person) : Bool
    is_account_email?(p.email)
  end
  singleton_method is_account?, p

  def is_account_email?(email : String) : Bool
    !account_for(email).nil?
  end
  singleton_method is_account_email?, email

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

