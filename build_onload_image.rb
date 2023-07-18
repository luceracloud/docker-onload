#!/usr/bin/env ruby
# Build helper for OpenOnload Docker images
# Copyright (c) 2015-2021 Neomantra BV.

require 'getoptlong'

$ONLOAD_VERSIONS = {
    '8.0.2.51'   => { :version => '8.0.2.51',   :md5sum => '6d13cfd3d68ad4f6b1f41fcb624f85cd', :driverid => '89ed1273b4d369806a6a03b8f3697c17', :package_url => 'https://www.xilinx.com/content/dam/xilinx/publications/solarflare/onload/openonload/8_0_2_51/SF-109585-LS-40-OpenOnload-Release-Package.zip' },
    '7.1.3.202'   => { :version => '7.1.3.202',   :md5sum => '6153f93f03c65b4d091e9247c195b58c', :driverid => '1d52732765feca797791b9668b14fb4e', :package_url => 'https://www.xilinx.com/content/dam/xilinx/publications/solarflare/onload/openonload/7-1-3-202/SF-109585-LS-37-OpenOnload-release-package.zip' },
}
$ONLOAD_VERSIONS['latest'] = $ONLOAD_VERSIONS['8.0.2.51'].dup

$IMAGE_FLAVORS = {
    'bionic'   => { :flavor => 'bionic' :os => 'Ubuntu 18.04 LTS'},
    'bullseye' => { :flavor => 'bullseye', :os => 'Debian 11' },
    'buster'   => { :flavor => 'buster', :os => 'Debian 10' },
    'centos7'  => { :flavor => 'centos7', :os => 'Centos 7'},
    'centos8'  => { :flavor => 'centos8', :os => 'Centos 8' },
    'focal'    => { :flavor => 'focal' , :os => 'Ubuntu 20.04 LTS'},
    'jammy'    => { :flavor => 'jammy', :os => 'Ubuntu 22.04 LTS' },
    'stretch'  => { :flavor => 'stretch', :os => 'Debian 9' }
}

###############################################################################

USAGE_STR = <<END_OF_USAGE
build_onload_image.rb [options]

ACTIONS
    --versions                show list of onload version name (use with -v to show all fields)
    --flavors                 show list of image flavors
    --gettag      <prefix>    show the autotag name of --autotag <prefix>

    --build                   show docker build command
    --execute                 execute docker build command

OPTIONS
    --flavor   -f  <flavor>   specify build <flavor> (required for --build or --execute)
    --onload   -o  <version>  specify onload <version> to build (default is 'latest')

    --url      -u  <url>      Override URL for "packaged" versions.

    --tag      -t  <tag>      tag image as <tag>
    --autotag  -a  <prefix>   tag image as <prefix><version>-<flavor>[-nozf]. 
                                 <prefix> is optional, but note without a <prefix> with colon,
                                 the autotag will be a name not an image-name:tag

    --zf           <truthy>   build with TCPDirect (zf)  (or not, if optional <truthy> is '0' or 'false')

    --arg          <arg>      pass '--build-arg <arg>' to "docker build"

    --quiet    -q             build quietly (pass -q to "docker build")
    --no-cache                pass --no-cache to "docker build"

    --execute  -x             also execute the build line

    --push     -p             push the built image

    --verbose  -v             verbose output
    --help     -h             show this help
END_OF_USAGE

$opts = {
    :action    => nil,
    :execute   => false,
    :push      => false,
    :ooversion => 'latest',
    :flavor    => nil,
    :tag       => nil,
    :autotag   => nil,
    :buildargs => [],
    :zf        => false,
    :quiet     => false,
    :cache     => true,
    :verbose   => 0
}

begin
    GetoptLong.new(
        [ '--versions',       GetoptLong::NO_ARGUMENT ],
        [ '--flavors',        GetoptLong::NO_ARGUMENT ],
        [ '--gettag',         GetoptLong::OPTIONAL_ARGUMENT ],
        [ '--build',          GetoptLong::NO_ARGUMENT ],
        [ '--onload',   '-o', GetoptLong::REQUIRED_ARGUMENT ],
        [ '--flavor',   '-f', GetoptLong::REQUIRED_ARGUMENT ],
        [ '--url',      '-u', GetoptLong::REQUIRED_ARGUMENT ],
        [ '--tag',      '-t', GetoptLong::REQUIRED_ARGUMENT ],
        [ '--autotag',  '-a', GetoptLong::OPTIONAL_ARGUMENT ],
        [ '--arg',            GetoptLong::REQUIRED_ARGUMENT ],
        [ '--zf',             GetoptLong::OPTIONAL_ARGUMENT ],
        [ '--quiet',    '-q', GetoptLong::NO_ARGUMENT ],
        [ '--no-cache',       GetoptLong::NO_ARGUMENT ],
        [ '--execute',  '-x', GetoptLong::NO_ARGUMENT ],
        [ '--push',     '-p' ,GetoptLong::NO_ARGUMENT ],
        [ '--verbose',  '-v', GetoptLong::NO_ARGUMENT ],
        [ '--help',     '-h', GetoptLong::NO_ARGUMENT ]
    ).each do |opt, arg|
        case opt
        when '--versions'
            $opts[:action] = :versions    
        when '--flavors'
            $opts[:action] = :flavors    
        when '--gettag'
            $opts[:action] = :gettag
            $opts[:autotag] = arg || '' if $opts[:autotag].nil?
        when '--build'
            $opts[:action] = :build
        when '--onload'
            if $opts[:ooversion] != 'latest' then
                STDERR << "ERROR: --onload can only be specified once\n"
                exit(-1)
            end
            $opts[:ooversion] = arg
        when '--flavor'
            if ! $opts[:flavor].nil? then
                STDERR << "ERROR: --flavor can only be specified once\n"
                exit(-1)
            end
            $opts[:flavor] = arg
        when '--url'
            $opts[:url] = arg
        when '--tag'
            $opts[:tag] = arg
        when '--autotag'
            $opts[:autotag] = arg
        when '--arg'
            $opts[:buildargs] << arg
        when '--zf'
            $opts[:zf] = true
            $opts[:zf] = false if arg == '0' || arg.downcase == 'false'
        when '--quiet'
            $opts[:quiet] = true
        when '--no-cache'
            $opts[:cache] = false
        when '--execute'
            $opts[:action] = :build
            $opts[:execute] = true
        when '--push'
            $opts[:push] = true
        when '--verbose'
            $opts[:verbose] += 1
        when '--help'
            $opts[:action] = :help
        end
    end
rescue StandardError => e
    STDERR << "ERROR: #{e.to_s}\n"
    exit(-1)
end

###############################################################################

def get_version()
    version = $opts[:ooversion]
    if version.nil? then
        STDERR << "ERROR: a valid version must be specified with --build (-b).  List with --versions\n"
        exit(-1)
    end
    if ! $ONLOAD_VERSIONS.has_key? version then
        STDERR << "ERROR: unknown onload version '#{version}'.  List with --versions\n"
        exit(-1)
    end
    return version
end


def get_flavor()
    flavor = $opts[:flavor]
    if flavor.nil? then
        STDERR << "ERROR: a valid flavor must be specified with --flavor (-f).   List with --flavors.\n"
        exit(-1)
    end
    if ! $IMAGE_FLAVORS.has_key? flavor then
        STDERR << "ERROR: unknown flavor '#{flavor}'.  List with --flavors.\n"
        exit(-1)
    end
    return flavor
end


def get_tag()
    # check tag arguments
    if ! $opts[:tag].nil? && ! $opts[:autotag].nil? then
        STDERR << "ERROR: cannot specify both --tag and --autotag (or --gettag with argument)\n"
        exit(-1)
    end

    if ! $opts[:tag].nil? then
        return $opts[:tag]
    end

    version = get_version()
    flavor = get_flavor()
    tag = $opts[:tag]
    if $opts[:autotag] then
        tag = "#{$opts[:autotag]}#{version}-#{flavor}#{$opts[:zf] ? "" : "-nozf"}"
    end
    return tag
end



###############################################################################


case $opts[:action]
when :versions
    if $opts[:verbose] == 0 then
        $ONLOAD_VERSIONS.each do |k, v|
            next if k == 'latest'
            STDOUT << sprintf("%s\n", v[:version])
        end
    else
        $ONLOAD_VERSIONS.each do |k, v|
            next if k == 'latest'
            STDOUT << sprintf("%-16s %s %s %s\n",
                v[:version], v[:md5sum],
                v[:driverid] || "",
                v[:package_url] || "")
        end
    end
when :flavors
    $IMAGE_FLAVORS.each do |k, v|
        STDOUT << sprintf("%s\n", v[:flavor])
    end
when :gettag
    if $opts[:tag].nil? && $opts[:autotag].nil? then
        STDERR << "ERROR: must specify either --tag and --autotag (or --gettag with argument)\n"
        exit(-1)
    end
    STDOUT << get_tag() << "\n"
when :build
    tag = get_tag()

    if $opts[:push] && !$opts[:execute] then
        STDERR << "--push requires --execute\n"
        exit(-1)
    end
    if $opts[:push] && tag.nil? then
        STDERR << "--push requires --tag or --autotag\n"
        exit(-1)
    end

    version = get_version()
    vdata = $ONLOAD_VERSIONS[version]
    cmd = "docker build --build-arg ONLOAD_VERSION=#{vdata[:version]} --build-arg ONLOAD_MD5SUM=#{vdata[:md5sum]} "
    package_url = $opts[:url] || vdata[:package_url]
    if ! package_url.nil? then
        cmd += " --build-arg ONLOAD_PACKAGE_URL='#{package_url}' "
    else
        # Force an empty OPEN_PACKAGE_URL to build legacy
        cmd += " --build-arg ONLOAD_PACKAGE_URL='' "
    end

    cmd += "--build-arg ONLOAD_WITHZF=1 " if $opts[:zf]
    $opts[:buildargs].each { |arg| cmd += "--build-arg #{arg} " }

    cmd += "-q " if $opts[:quiet]
    cmd += "--no-cache " if ! $opts[:cache]
    cmd += "-t #{tag} " if ! tag.nil?

    flavor = get_flavor()
    cmd += "-f #{flavor}/Dockerfile ."

    STDOUT << cmd << "\n"
    if $opts[:execute] then
        res = system(cmd)
        if !res then
            STDERR << "ERROR: docker build failed with code #{$?}\n"
        elsif $opts[:push] then
            res = system("docker push #{tag}")
            if !res then
                STDERR << "ERROR: docker push failed with code #{$?}\n"
            end
        end
    end

when :help
    STDERR << USAGE_STR << "\n";
    exit(0)
when nil
    STDERR << "no action specified. try --help\n";
    exit(-1)
end
