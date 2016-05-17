FROM ubuntu:precise

# Required system packages
RUN apt-get update \
    && apt-get install -y \
        wget \
        unzip \
        build-essential \
        ruby1.9.1-dev \
        ruby1.9.3 \
        libreadline6-dev \
        libncurses5-dev \
        libxslt1-dev \
        libgd2-xpm-dev \
        libgeoip-dev \
        perl \
    && gem install fpm

RUN mkdir /build /build/root
WORKDIR /build

# Download packages
RUN wget https://openresty.org/download/openresty-1.9.7.4.tar.gz \
    && tar xfz openresty-1.9.7.4.tar.gz \
    && wget https://github.com/simpl/ngx_devel_kit/archive/v0.2.19.tar.gz -O ngx_devel_kit-0.2.19.tar.gz \
    && tar xfz ngx_devel_kit-0.2.19.tar.gz \
    && wget https://www.openssl.org/source/openssl-1.0.2h.tar.gz \
    && tar xfz openssl-1.0.2h.tar.gz \
    && wget ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-8.37.tar.gz \
    && tar xfz pcre-8.37.tar.gz \
    && wget http://zlib.net/zlib-1.2.8.tar.gz \
    && tar xfz zlib-1.2.8.tar.gz \
    && wget https://keplerproject.github.io/luarocks/releases/luarocks-2.2.2.tar.gz \
    && tar xfz luarocks-2.2.2.tar.gz

# Compile and install openresty
RUN cd /build/openresty-1.9.7.4 \
    && ./configure \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_gzip_static_module \
        --with-debug \
        --with-openssl=/build/openssl-1.0.2h \
        --with-pcre=/build/pcre-8.37 \
        --with-pcre-jit \
        --with-zlib=/build/zlib-1.2.8 \
        --with-cc-opt='-O2 -fstack-protector --param=ssp-buffer-size=4 -Wformat -Werror=format-security -D_FORTIFY_SOURCE=2' \
        --with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro' \
        --prefix=/usr/share/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --http-log-path=/var/log/nginx/access.log \
        --error-log-path=/var/log/nginx/error.log \
        --lock-path=/var/lock/nginx.lock \
        --pid-path=/run/nginx.pid \
        --http-client-body-temp-path=/var/lib/nginx/body \
        --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
        --http-proxy-temp-path=/var/lib/nginx/proxy \
        --http-scgi-temp-path=/var/lib/nginx/scgi \
        --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
        --user=www-data \
        --group=www-data \
        --with-ipv6 \
        --with-http_realip_module \
        --with-http_auth_request_module \
        --with-http_addition_module \
        --with-http_dav_module \
        --with-http_geoip_module \
        --with-http_image_filter_module \
        --with-http_sub_module \
        --with-http_xslt_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-threads \
    && make -j4 \
    && make install DESTDIR=/build/root

# Compile LuaRocks
RUN mkdir -p /usr/share/nginx && ln -s /build/root/usr/share/nginx/luajit /usr/share/nginx/luajit \
    && cd /build/luarocks-2.2.2 \
    && ./configure --prefix=/usr/share/nginx/luajit \
            --with-lua=/usr/share/nginx/luajit \
            --lua-suffix=jit-2.1.0-beta1 \
            --with-lua-include=/usr/share/nginx/luajit/include/luajit-2.1 \
            --with-downloader=wget \
            --with-md5-checker=openssl \
    && make build \
    && make install DESTDIR=/build/root \
    && rm -rf /usr/share/nginx

COPY scripts/* nginx-scripts/
COPY conf/* nginx-conf/

# Add extras to the build root
RUN cd /build/root \
    && mkdir \
        etc/init.d \
        etc/logrotate.d \
        etc/nginx/sites-available \
        etc/nginx/sites-enabled \
        var/lib \
        var/lib/nginx \
    && mv usr/share/nginx/bin/resty usr/sbin/resty && rm -rf usr/share/nginx/bin \
    && mv usr/share/nginx/nginx/html usr/share/nginx/html && rm -rf usr/share/nginx/nginx \
    && rm etc/nginx/*.default \
    && cp /build/nginx-scripts/init etc/init.d/nginx \
    && chmod +x etc/init.d/nginx \
    && cp /build/nginx-conf/logrotate etc/logrotate.d/nginx \
    && cp /build/nginx-conf/nginx.conf etc/nginx/nginx.conf \
    && cp /build/nginx-conf/default etc/nginx/sites-available/default

# Build deb
RUN fpm -s dir -t deb \
    -n openresty \
    -v 1.9.7.4-minted \
    -C /build/root \
    -p openresty_VERSION_ARCH.deb \
    --description 'a high performance web server and a reverse proxy server' \
    --url 'http://openresty.org/' \
    --category httpd \
    --maintainer 'Gabriel Laden <gabrielladen@minted.com>' \
    --depends wget \
    --depends unzip \
    --depends libncurses5 \
    --depends libreadline6 \
    --depends libxslt1.1 \
    --depends libgd2-xpm \
    --depends libgeoip1 \
    --deb-build-depends build-essential \
    --replaces 'nginx-full' \
    --provides 'nginx-full' \
    --conflicts 'nginx-full' \
    --replaces 'nginx-common' \
    --provides 'nginx-common' \
    --conflicts 'nginx-common' \
    --after-install nginx-scripts/postinstall \
    --before-install nginx-scripts/preinstall \
    --after-remove nginx-scripts/postremove \
    --before-remove nginx-scripts/preremove \
    etc run usr var
