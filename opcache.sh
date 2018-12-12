get_available_memory(){
    [[ -z $IS_X86_64 ]] && get_os_type

    AVAILABLE_MEMORY=$(free | grep Mem | awk '{print $2}')
    if [[ $IS_OPENVZ -gt 0 ]]; then
        if [[ -z $AVAILABLE_MEMORY ]]; then
            mem4kblock=`cat /proc/user_beancounters | \
                grep vmguarpages|awk '{print $4}'`
            mem4kblock2=`cat /proc/user_beancounters | \
                grep privvmpages|awk '{print $4}'`
            if [[ ${mem4kblock2} -gt ${mem4kblock} ]]; then
                AVAILABLE_MEMORY=$(echo "${mem4kblock} * 4"|bc)
            else
                AVAILABLE_MEMORY=$(echo "${mem4kblock2} * 4"|bc)
            fi
        fi
    fi

    AVAILABLE_MEMORY_MB=$(( $AVAILABLE_MEMORY / 1024 ))

    [[ ( $IS_X86_64 -eq 0 ) && ( $AVAILABLE_MEMORY_MB -gt 4096 ) ]] && \
        AVAILABLE_MEMORY_MB=4096
}



        opcache_template=/etc/ansible/bvat_conf/opcache.ini.bx
        opcache_memory_mb=$(( $AVAILABLE_MEMORY_MB/8 ))
        [[ -z $opcache_memory_mb ]] && opcache_memory_mb=64
        [[ $opcache_memory_mb -lt 64 ]] && opcache_memory_mb=64
        [[ $opcache_memory_mb -gt 2048 ]] && opcache_memory_mb=2048

        opcache_memory_strings=$(( $opcache_memory_mb/4 ))

        opcache_config=/etc/php.d/10-opcache.ini
        [[ "$PHP_VERSION" == "5.4" ]] && opcache_config=/etc/php.d/opcache.ini

        # delete old config file; if there is one
        [[ ( "$PHP_VERSION" != "5.4" ) && \
            ( -f /etc/php.d/opcache.ini ) ]] && \
            rm -f /etc/php.d/opcache.ini

        # update opcache config
        if [[ -f $opcache_template ]]; then
            cat $opcache_template | \
                sed -e "s:__MEMORY__:$opcache_memory_mb:;s:__MEMORYSTR__:$opcache_memory_strings:;" \
                > $opcache_config 2>/dev/null && \
                log_to_file "Update opcache config=$opcache_config"
        fi
