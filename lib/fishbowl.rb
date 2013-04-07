require 'socket'
require 'base64'
require 'singleton'
require 'digest/md5'

require 'nokogiri'

require 'fishbowl/ext'

require 'fishbowl/version'
require 'fishbowl/errors'
require 'fishbowl/requests'
require 'fishbowl/objects'

module Fishbowl # :nodoc:
  class Connection
    include Singleton
    extend Requests
   
    def self.connect(options = {})
      raise Fishbowl::Errors::MissingHost if options[:host].nil?

      @host = options[:host]
      @port = options[:port].nil? ? 28192 : options[:port]

      @connection = TCPSocket.new @host, @port
      @key = nil
      self.instance
    end

    def self.login(options = {})
      raise Fishbowl::Errors::ConnectionNotEstablished if @connection.nil?
      raise Fishbowl::Errors::MissingUsername if options[:username].nil?
      raise Fishbowl::Errors::MissingPassword if options[:password].nil?

      @username, @password = options[:username], options[:password]

      code, message, _ = Fishbowl::Objects::BaseObject.new.send_request(login_request, 'LoginRs')

      Fishbowl::Errors.confirm_success_or_raise(code.to_i)

      self.instance
    end

    def self.host
      @host
    end

    def self.port
      @port
    end

    def self.username
      @username
    end

    def self.password
      @password
    end

    def self.send(request, expected_response = 'FbiMsgRs')
      write(request)
      get_response(expected_response)
    end

    def self.close
      @connection.close
      @connection = nil
    end

  private

    def self.login_request
      Nokogiri::XML::Builder.new do |xml|
        xml.request {
          xml.LoginRq {
            xml.IAID          "11"
            xml.IAName        "Ruby Fishbowl"
            xml.IADescription "Ruby Fishbowl"
            xml.UserName      @username
            xml.UserPassword  encoded_password
          }
        }
      end
    end

    def self.encoded_password
      Base64.encode64(Digest::MD5.digest(@password)).chomp
    end

    def self.write(request)
      body = request.to_xml
      size = [body.size].pack("L>")

      @connection.write(size)
      @connection.write(body)
    end

    def self.get_response(expectation)
      length = @connection.recv(4).unpack("L>").join('').to_i
      response = Nokogiri::XML.parse(@connection.recv(length))
      
      if(@key.nil?)
        @key = response.xpath("//Ticket/Key/text()").first
      end
      
      status_code = response.xpath("//FbiMsgsRs/@statusCode").first.value
      message_code = response.xpath("//#{expectation}/@statusCode").first.value

      status_message = nil
     
      [status_code, status_message, response]
    end
  end
end
