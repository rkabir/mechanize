##
# This class is used to manage the Cookies that have been returned from
# any particular website.

class Mechanize::CookieJar

  # add_cookie wants something resembling a URI.

  FakeURI = Struct.new(:host) # :nodoc:

  attr_reader :jar

  def initialize
    @jar = {}
  end

  def initialize_copy other # :nodoc:
    @jar = Marshal.load Marshal.dump other.jar
  end

  # Add a cookie to the Jar.
  def add(uri, cookie)
    return unless cookie.acceptable_from_uri?(uri)

    normal_domain = cookie.domain.downcase

    @jar[normal_domain] ||= {} unless @jar.has_key?(normal_domain)

    @jar[normal_domain][cookie.path] ||= {}
    @jar[normal_domain][cookie.path][cookie.name] = cookie

    cookie
  end

  # Fetch the cookies that should be used for the URI object passed in.
  def cookies(url)
    cleanup
    url.path = '/' if url.path.empty?

    [].tap { |cookies|
      @jar.each { |domain, paths|
        paths.each { |path, hash|
          hash.each_value { |cookie|
            next if cookie.expired? || !cookie.valid_for_uri?(url)
            cookies << cookie
          }
        }
      }
    }
  end

  def empty?(url)
    cookies(url).length > 0 ? false : true
  end

  def to_a
    cleanup

    @jar.map do |domain, paths|
      paths.map do |path, names|
        names.values
      end
    end.flatten
  end

  # Save the cookie jar to a file in the format specified.
  #
  # Available formats:
  # :yaml  <- YAML structure
  # :cookiestxt  <- Mozilla's cookies.txt format
  def save_as(file, format = :yaml)
    jar = dup
    jar.cleanup true

    open(file, 'w') { |f|
      case format
      when :yaml then
        load_yaml

        YAML.dump(jar.jar, f)
      when :cookiestxt then
        jar.dump_cookiestxt(f)
      else
        raise ArgumentError, "Unknown cookie jar file format"
      end
    }

    self
  end

  # Load cookie jar from a file in the format specified.
  #
  # Available formats:
  # :yaml  <- YAML structure.
  # :cookiestxt  <- Mozilla's cookies.txt format
  def load(file, format = :yaml)
    @jar = open(file) { |f|
      case format
      when :yaml then
        load_yaml

        YAML.load(f)
      when :cookiestxt then
        load_cookiestxt(f)
      else
        raise ArgumentError, "Unknown cookie jar file format"
      end
    }

    cleanup

    self
  end

  def load_yaml # :nodoc:
    begin
      require 'psych'
    rescue LoadError
    end

    require 'yaml'
  end

  # Clear the cookie jar
  def clear!
    @jar = {}
  end

  # Read cookies from Mozilla cookies.txt-style IO stream
  def load_cookiestxt(io)
    now = Time.now

    io.each_line do |line|
      line.chomp!
      line.gsub!(/#.+/, '')
      fields = line.split("\t")

      next if fields.length != 7

      expires_seconds = fields[4].to_i
      expires = (expires_seconds == 0) ? nil : Time.at(expires_seconds)
      next if expires and (expires < now)

      c = Mechanize::Cookie.new(fields[5], fields[6])
      c.domain = fields[0]
      # Field 1 indicates whether the cookie can be read by other machines at
      # the same domain.  This is computed by the cookie implementation, based
      # on the domain value.
      c.path = fields[2]               # Path for which the cookie is relevant
      c.secure = (fields[3] == "TRUE") # Requires a secure connection
      c.expires = expires             # Time the cookie expires.
      c.version = 0                   # Conforms to Netscape cookie spec.

      add(FakeURI.new(c.domain), c)
    end

    @jar
  end

  # Write cookies to Mozilla cookies.txt-style IO stream
  def dump_cookiestxt(io)
    to_a.each do |cookie|
      fields = []
      fields[0] = cookie.domain

      if cookie.domain =~ /^\./
        fields[1] = "TRUE"
      else
        fields[1] = "FALSE"
      end

      fields[2] = cookie.path

      if cookie.secure == true
        fields[3] = "TRUE"
      else
        fields[3] = "FALSE"
      end

      fields[4] = cookie.expires.to_i.to_s

      fields[5] = cookie.name
      fields[6] = cookie.value
      io.puts(fields.join("\t"))
    end
  end

  protected

  # Remove expired cookies
  def cleanup session = false
    @jar.each do |domain, paths|
      paths.each do |path, names|
        names.each do |cookie_name, cookie|
          paths[path].delete(cookie_name) if
            cookie.expired? or (session and cookie.session)
        end
      end
    end
  end
end

