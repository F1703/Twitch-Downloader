#!/bin/bash

# COLORES 
greenColour="\e[0;32m\033[1m"
endColour="\033[0m\e[0m"
whiteColor="\e[0;37m\033[1m"
yellowColour="\e[0;33m\033[1m"

cookie=/tmp/cookies_tw.txt
r_default=720p
hilos_default=100 
VERBOSE=0


# Lista de comandos requeridos
DEPENDENCIAS=(jq ffmpeg xargs)

for cmd in "${DEPENDENCIAS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${yellowColour}[-] La herramienta '$cmd' no está instalada. Por favor instalala antes de continuar.${endColour}"
        exit 1
    fi
done

trap ctrl_c INT

vlog() {
    [[ $VERBOSE -eq 1 ]] && echo -e "$@"
}

ctrl_c() {
	echo -e "${yellowColour}[!] Saliendo...${endColour}"
    exit 1
}

modo_uso() {
    echo -e "${yellowColour}Modo de uso:  $(basename $0) [OPCIONES] ${endColour}"
    echo  "Ejemplo 1: $0 -c 123456788 -r 1080 -w 200"
    echo -e "\nOPCIONES:"
    echo -e " -c 1234567890 \t Codigo identificador del video. Ej 1234567890"
    echo -e " -r 1080 \t Resolucion del video: 1080 (1920x1080), 720 (1280x720), 480 (852x480) ,360 (640x360), 160 (284x160)."
    echo -e " -w 50 \t\t Numero de workers para descargar en paralelo. Por defecto 100"
    echo -e " -v \t\t Modo verboso\n"
    echo -e " -h \t\t Muestra esta ayuda y termina\n"
    exit 0
}

procesar() {
    VOD_ID=$OPTARG_C
    r_default=$([[ $OPTARG_R -ne "" ]] && echo $OPTARG_R"p"  || echo $r_default )
    hilos=$([[ $OPTARG_W -ne "" ]] && echo $OPTARG_W || echo $hilos_default )

    folder_parts=$VOD_ID"_$r_default/parts/"
    mkdir -p $folder_parts
        
    folder_data=$VOD_ID"_"$r_default"/data/"
    mkdir -p $folder_data
    
    ACMB="eyJBcHBWZXJzaW9uIjoiNGNiNzFmZWUtNGEyMy00OTY1LWI3MDEtNGYzZmU2Nzc4NWFkIn0%3D"
    P_RANDOM="458758"
    PLAY_SESSION_ID="c31fa96cb66fc72c3c29526bb31ec693"
    SIG="bd166ff81277d83f8e7f04c2320bf25e44ae8276"
    CLIENT_ID="kimne78kx3ncx6brgo4mv6wki5h1ko"
    PLAYER_TYPE="site"
    UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
    GQL_QUERY=$(printf '{"operationName":"PlaybackAccessToken_Template","query":"query PlaybackAccessToken_Template($login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, $playerType: String!, $platform: String!) { streamPlaybackAccessToken(channelName: $login, params: {platform: $platform, playerBackend: \\"%s\\", playerType: $playerType}) @include(if: $isLive) { value signature authorization { isForbidden forbiddenReasonCode } __typename } videoPlaybackAccessToken(id: $vodID, params: {platform: $platform, playerBackend: \\"%s\\", playerType: $playerType}) @include(if: $isVod) { value signature __typename }}","variables":{"isLive":false,"login":"","isVod":true,"vodID":"%s","playerType":"%s","platform":"%s"}}' \
    "mediaplayer" "mediaplayer" "$VOD_ID" "$PLAYER_TYPE" "web")
    OUTFILE="${VOD_ID}_signature.json"

    curl -s "https://gql.twitch.tv/gql" \
    -H "accept: */*" \
    -H "accept-language: en-US" \
    -H "authorization: undefined" \
    -H "cache-control: no-cache" \
    -H "client-id: $CLIENT_ID" \
    -H "content-type: text/plain; charset=UTF-8" \
    -H "origin: https://www.twitch.tv" \
    -H "pragma: no-cache" \
    -H "referer: https://www.twitch.tv/" \
    -H "user-agent: $UA" \
    --data-raw "$GQL_QUERY" \
    -o "$folder_data$OUTFILE"

   
    if ! jq empty "$folder_data$OUTFILE" 2>/dev/null; then
        # echo -e "${yellowColour}[-] JSON no válido. Abortando.${endColour}"
        vlog "${yellowColour}[-] JSON no válido. Abortando.${endColour}"
        exit 1
    fi

    SIG=$(cat "$folder_data$OUTFILE" | jq -r '.data.videoPlaybackAccessToken.signature')
    TOKEN=$(cat "$folder_data$OUTFILE" | jq -r '.data.videoPlaybackAccessToken.value')
    TOKEN_ENCODED=$(printf "%s" "$TOKEN" | jq -s -R -r @uri)

    if [[ -z "$SIG" ]]; then
        # echo -e "${yellowColour}[-] No se pudo obtener un signature válido. Abortando.${endColour}"
        vlog "${yellowColour}[-] No se pudo obtener un signature válido. Abortando.${endColour}"
        exit 1
    fi

    BASE_URL="https://usher.ttvnw.net/vod/v2/${VOD_ID}.m3u8"
    QUERY="acmb=${ACMB}&allow_source=true&browser_family=chrome&browser_version=142.0"
    QUERY="${QUERY}&cdm=wv&enable_score=true&include_unavailable=true"
    QUERY="${QUERY}&multigroup_video=false&os_name=Linux&os_version=undefined"
    QUERY="${QUERY}&p=${P_RANDOM}&platform=web&play_session_id=${PLAY_SESSION_ID}"
    QUERY="${QUERY}&player_backend=mediaplayer&player_version=1.47.0-rc.3"
    QUERY="${QUERY}&playlist_include_framerate=true&reassignments_supported=true"
    QUERY="${QUERY}&sig=${SIG}&supported_codecs=av1,h264"
    QUERY="${QUERY}&token=${TOKEN_ENCODED}&transcode_mode=cbr_v1"

    FULL_URL="${BASE_URL}?${QUERY}"

    curl -s "$FULL_URL" \
    -H "User-Agent: $UA" \
    -H "Accept: application/x-mpegURL, application/vnd.apple.mpegurl, application/json, text/plain" \
    -o "${folder_data}${VOD_ID}_file.m3u8"

    url_file=$(grep '\.m3u8' "${folder_data}${VOD_ID}_file.m3u8" | sort -u -r | grep "$r_default"  | sort -u -r | head -1 )

    if [[ -z "$url_file" ]]; then
        # echo -e "${yellowColour}[-] No se encontró una URL válida. Saliendo...${endColour}"
        vlog "${yellowColour}[-] No se encontró una URL válida. Saliendo...${endColour}"
        exit 1
    fi

    curl -s -X GET "$url_file" > "$folder_data$VOD_ID.$r_default.m3u8"

    last_part=$(echo "$url_file" | awk '{print $NF}' FS='/')
    url_video=$(echo "$url_file" | awk -F $last_part '{print $1}')
    
    echo -e "${yellowColour}[+]${endColour}${whiteColor} Descargado todas las de partes de video ${endColour}"

    ts_list=$(grep "\.ts" "$folder_data$VOD_ID.$r_default.m3u8")

    # CONTAR CANTIDAD DE ARCHIVOS TS 
    total_parts=$(echo "$ts_list" | wc -l)
    vlog "${yellowColour}[+]${endColour}${whiteColor} Total de partes a descargar: $total_parts ${endColour}"

    # DESCARGANDO EN PARALELO CON XARGS Y WGET (wget ya que me permite reconectar la parte descargada)
    max_retries=4
    fail_log=$(mktemp)

    export VERBOSE
    echo "$ts_list" | nl | xargs -P "$hilos" -I {} bash -c '
        line=($0)
        num=$(printf "%05d" "${line[0]}")
        part=${line[1]}
        part_path="'"$folder_parts"'$part.mp4"

        [[ $VERBOSE -eq 1 ]] && echo "[#$num/'$total_parts'] ⏳ Descargando $part" >&2

        for attempt in $(seq 1 '"$max_retries"'); do
            wget --tries=2 \
                --no-check-certificate \
                --retry-connrefused \
                --wait=1 \
                --quiet \
                --continue \
                "'"$url_video"'$part" \
                --output-document="$part_path"

            if [[ -s "$part_path" ]]; then
                [[ $VERBOSE -eq 1 ]] && echo "[#$num/'$total_parts'] ✅ Completado $part" >&2
                break
            else
                [[ $VERBOSE -eq 1 ]] && echo "[#$num/'$total_parts'] ❌ Falló intento $attempt para $part" >&2
                sleep 1
            fi
        done

        if [[ ! -s "$part_path" ]]; then
            [[ $VERBOSE -eq 1 ]] && echo "$part" >> "'"$fail_log"'"
        fi
    ' {}

    wait

    # Reintentar archivos fallidos
    if [[ -s "$fail_log" ]]; then
        vlog "🔁 Reintentando fragmentos fallidos:" >&2
        while read part; do
            vlog "↩️ Reintentando $part..." >&2
            wget --tries=4 \
                --no-check-certificate \
                --retry-connrefused \
                --wait=2 \
                --quiet \
                --continue \
                "$url_video$part" \
                --output-document="$folder_parts$part.mp4"

            if [[ -s "$folder_parts$part.mp4" ]]; then
                vlog "✅ Reintento exitoso: $part" >&2
            else
                vlog "❌ Aún fallido tras reintentos: $part" >&2
            fi
        done < "$fail_log" 
    fi

    rm -f "$fail_log"
    
    # GENERANDO LISTADO DE TS DESCARGADOS
    filesMP4=$VOD_ID"_"$r_default"/files.txt" 
    echo "$ts_list" | xargs -I {} echo "file 'parts/{}.mp4'" >> $filesMP4
     
    # UNIENDO VIDEOS
    logInfo=$folder_data"ffmpeg.log"
    time=$(date +%H%M%S)
    video=$VOD_ID"_"$r_default"/"$VOD_ID"_"$r_default"_"$time".mp4"

    echo -e "${yellowColour}[+]${endColour}${whiteColor} Uniendo partes con ffmpeg.${endColour}"
    
    ffmpeg -safe 0  -f concat -i $filesMP4  -bsf:a aac_adtstoasc  -vcodec copy $video >$logInfo 2>&1 

    if [[ $? -ne 0 ]]; then
        echo -e "${yellowColour}[-] Error al unir video. Verifica el log: $logInfo${endColour}"
        exit 1
    fi

    echo -e "${yellowColour}[+]${endColour}${whiteColor} Proceso terminado. ${endColour}"
    echo -e "${yellowColour}[+]${endColour}${whiteColor} Video: $video ${endColour}"

    rm -fr "$filesMP4" 2>/dev/null
    rm -fr "$folder_data" 2>/dev/null
    rm -fr "$folder_parts" 2>/dev/null

    exit 0

}
 

[[ $# -eq 0 ]] && modo_uso

VARIABLE_C=0
VARIABLE_L=0

while getopts ":c:r:w:l:hv" opt; do
    case $opt in
        c) VARIABLE_C=1; OPTARG_C="$OPTARG" ;;  # Código de video
        r) OPTARG_R="$OPTARG" ;;                # Resolución
        w) OPTARG_W="$OPTARG" ;;                # Workers
        v) VERBOSE=1 ;;                      
        h) modo_uso ;;
        \?) echo -e "${yellowColour}[-]${endColour} Opción no válida: -$OPTARG"; exit 1 ;;
        :) echo -e "${yellowColour}[!]${endColour} La opción -$OPTARG requiere un argumento"; exit 1 ;;
    esac
done

shift $((OPTIND-1))


# -c 123456780  
if [[ $VARIABLE_C -ne 1 ]]  ; then
    echo -e "${yellowColour}[+]${endColour}${whiteColor} Se necesita un codigo de video para continuar ${endColour}"
    modo_uso
fi

procesar "$OPTARG_C" "$OPTARG_R" "$OPTARG_W"

