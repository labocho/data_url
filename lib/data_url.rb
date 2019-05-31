require "data_url/version"

require "strscan"
require "base64"

# RFC2397 The "data" URL scheme
# https://tools.ietf.org/html/rfc2397
class DataUrl
  class Error < StandardError; end
  class ParseError < Error; end

  # RFC2045 Multipurpose Internet Mail Extensions (MIME) Part One: Format of Internet Message Bodies
  # https://tools.ietf.org/html/rfc2045#section-5.1
  RFC2045_TOKEN = ("[[:ascii:]&&[:^cntrl:]&&[^" + Regexp.escape(%( ()<>@,;:\\"/[]?=)) + "]]+").freeze
  RFC2045_TOKEN_INCLUDES_TSPECIAL = "[[:ascii:]&&[:^cntrl:]]+".freeze

  # RFC2396 Uniform Resource Identifiers (URI): Generic Syntax
  # https://tools.ietf.org/html/rfc2396#section-2.3
  RFC2396_NOT_UNRESERVED_CHARACTER = Regexp.compile(
    (
      "[^a-zA-Z0-9" + Regexp.escape("-_.!~*'()") + "]"
    ).encode("ascii-8bit"),
  ).freeze

  class << self
    # CGI.unescape/escape treats '+' in Base64 as space.
    # These methods uses just percent encoding.
    def unescape(s)
      buffer = ""
      s = StringScanner.new(s)

      until s.eos?
        case
        when t = s.scan(/[^%]+/)
          buffer << t
        when s.scan(/%([0-9A-Fa-f]{2})/)
          buffer << s[1].to_i(16).chr
        else
          raise "Invalid percent encoding at #{s.pos}: #{s.string}"
        end
      end

      buffer
    end

    def escape(s)
      s.dup.force_encoding("ascii-8bit").gsub(RFC2396_NOT_UNRESERVED_CHARACTER) do |c|
        "%" + c.ord.to_s(16).upcase.rjust(2, "0")
      end
    end

    def parse(str)
      s = StringScanner.new(str)
      raise parse_error(s) unless s.scan(/data:/)

      # mediatype
      if s.scan(%r{([^;,/]+)/([^;,]+)})
        type = unescape(s[1])
        unless type =~ Regexp.compile("\\A" + RFC2045_TOKEN + "\\z")
          raise parse_error(s)
        end

        subtype = unescape(s[2])
        unless subtype =~ Regexp.compile("\\A" + RFC2045_TOKEN + "\\z")
          raise parse_error(s)
        end
      end

      parameters = {}
      while s.scan(%r{;([^=;,]+)=([^;,]+)})
        attribute = unescape(s[1])
        unless attribute =~ Regexp.compile("\\A" + RFC2045_TOKEN + "\\z")
          raise parse_error(s)
        end

        value = unescape(s[2])
        unless value =~ Regexp.compile("\\A" + RFC2045_TOKEN_INCLUDES_TSPECIAL + "\\z")
          raise parse_error(s)
        end

        parameters[attribute] = value
      end

      base64 = s.scan(/;base64/) != nil

      unless s.scan(/,/)
        raise parse_error(s)
      end

      data = unescape(s.scan(Regexp.compile(RFC2045_TOKEN_INCLUDES_TSPECIAL)) || "")
      puts data
      unless s.eos?
        raise parse_error(s)
      end

      new(
        base64 ? Base64.decode64(data) : data,
        content_type: type && subtype ? "#{type}/#{subtype}" : nil,
        parameters: parameters,
        base64: base64,
      )
    end

    def parse_error(s)
      ParseError.new("Cannot parse at #{s.pos}: #{s.string}")
    end
  end

  attr_reader :data, :content_type, :parameters

  def initialize(data, content_type: nil, parameters: {}, base64: true)
    @data = data
    @content_type = content_type
    @parameters = parameters
    @base64 = base64
  end

  def base64?
    @base64
  end

  def to_s
    buffer = "data:"

    if content_type
      buffer << content_type.split("/", 2).map{|s| escape(s) }.join("/")
    end

    parameters.each do |attribute, value|
      buffer << ";" + escape(attribute) + "=" + escape(value)
    end

    if base64?
      buffer << ";base64,"
      buffer << Base64.strict_encode64(data)
    else
      buffer << ","
      buffer << escape(data)
    end

    buffer
  end

  private
  def escape(s)
    self.class.escape(s)
  end
end
