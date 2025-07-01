# Twitch Downloader en Bash

Script en Bash para descargar videos (VODs) completos desde canales de **Twitch**, sin usar la API oficial. Permite listar videos por usuario y descargar VODs por ID 

---

## 🔧 Características

* Descarga videos completos (VODs) de Twitch por ID
* Listado completo de videos para un canal
* Selección de resolución (1080, 720, etc.)

---

## 📆 Requisitos

* jq
* ffmpeg
* xargs
* wget

Puedes instalar todo en Ubuntu con:

```bash
sudo apt update && sudo apt install -y jq ffmpeg wget findutils
```

---

## ⚡ Uso

```bash
# Descargar un video por ID
./twitch-downloader.sh -c <video_id> -r <resolucion> -w <workers>

# Listar todos los videos de un canal
./twitch-downloader.sh -l <userId>

# Ver ayuda
./twitch-downloader.sh -h
```

---

## 🔍 Ejemplos

```bash
# Descargar video ID 123456789 a 720p con 100 workers
./twitch-downloader.sh -c 123456789 -r 720 -w 100

# Listar VODs del canal "auronplay"
./twitch-downloader.sh -l auronplay
```

---

## 🎥 Demostración en video

Puedes ver una demostración completa del funcionamiento del script en el siguiente video:

![Demo GIF](video/video.gif)
 
