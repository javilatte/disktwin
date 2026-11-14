# disktwin

**La copia que necesitas cuando no necesitas RAID.**

disktwin convierte un segundo disco en el **gemelo vivo** de tu disco de datos. Lo que añades, cambias o borras aparece en el gemelo a los pocos segundos. Además **vigila la salud de tus discos** con SMART y te avisa cuando algo no va bien.

Sin array, sin reformatear y sin `mdadm`: tienes dos discos normales con archivos normales, y uno es siempre la copia del otro.

> 🇬🇧 [Read in English](README.md)

> ⚠️ **No está listo para producción.** disktwin es un conjunto de scripts de shell cuidadosos, pensados para el ordenador de casa, el centro multimedia o el homelab. No es para datos críticos de una empresa. Si perder unos segundos de cambios, o tener que cambiar de disco a mano, sería un problema serio para ti, lo que necesitas es un RAID de verdad, y además copias de seguridad.

## Por qué

Tienes un disco lleno de fotos, vídeos y documentos, un disco libre, y la sensación de que deberías "tener una copia".

La respuesta de manual es RAID 1, pero para esto resulta pesado:

- hay que borrar los dos discos y montarlo todo alrededor de un array;
- conviene que los dos discos sean iguales en tamaño y tipo;
- la copia solo se puede leer con `mdadm` o ZFS;
- y no te protege de tus propios errores: un `rm -rf` o un ransomware también se replican al instante.

disktwin se queda con lo útil, una segunda copia siempre al día, y se ahorra el resto.

## disktwin frente a RAID 1

| | RAID 1 (mdadm / ZFS) | disktwin |
|---|---|---|
| Montarlo | Reformatear los dos discos, crear el array, configurar mdadm e initramfs | Rellenar un archivo de configuración y ejecutar dos scripts |
| Datos que ya tienes | Hay que sacarlos antes y volver a meterlos | Se usan tal cual |
| Discos distintos (tamaño, tipo, USB, NVMe + HDD) | Se desaprovecha espacio o da guerra | Sin problema |
| Leer la copia en otro ordenador | Hace falta mdadm o ZFS | Son archivos normales: lo conectas a Windows o Mac |
| **Borrado masivo por error** | **Se replica en los dos discos al instante** | Se bloquea y te avisa |
| Avisos de salud de los discos | Se configuran aparte | Incluidos (SMART → escritorio y terminal) |
| Si muere un disco | Sigue funcionando sin cortes ✅ | La copia está ahí; el cambio es manual |
| Disco de sistema o arranque | ✅ | ❌ Solo discos de datos |
| Retraso hasta que el cambio llega a la copia | 0 | ~3 segundos |

## Qué hace

- **Espejo en un solo sentido, del origen al gemelo.**
  - **Al momento:** un servicio de usuario vigila el origen con `inotifywait`. Unos segundos después de cada tanda de cambios (`SETTLE_SECONDS`), sincroniza **solo lo que ha cambiado**:
    - si se crea, modifica o borra un archivo, se revisa únicamente su carpeta, sin entrar en las subcarpetas;
    - si aparece una carpeta nueva (creada o movida al origen), se copia entera;
    - si se borra una carpeta, se borra en el gemelo revisando solo la carpeta que la contenía.

    Cada cambio tarda una fracción de segundo, aunque el disco tenga decenas de miles de archivos.
  - **Cada hora:** un cronjob hace una sincronización completa, por si se escapó algún cambio (por ejemplo, mientras el servicio estaba parado).
- **Vigilancia SMART** con `smartd`: avisa si la salud falla, si aparecen sectores reasignados, pendientes o ilegibles, si suben los errores, si falla un autotest o si la temperatura es crítica. En los discos SATA lanza un test corto cada día y uno largo cada semana.
- **Avisos que no se te escapan:**
  - notificación crítica de escritorio en el momento;
  - banner rojo en cada terminal nueva hasta que lo marcas como visto;
  - recordatorio al iniciar sesión si quedan alertas pendientes.

### Seguridad

- Las particiones se localizan **por UUID**, nunca por ruta. Si el origen no está montado, **no se sincroniza** (así nunca se vacía el gemelo contra un directorio vacío), y te avisa.
- Si el gemelo no está montado exactamente donde se espera, no se sincroniza, y te avisa.
- **Los borrados masivos se bloquean:** si una sincronización va a borrar más de `MAX_DELETE` archivos, se para y te avisa. Si el borrado es intencionado: `disktwin-sync --force`.
- Solo se ejecuta un `rsync` a la vez (`flock`).

## Instalación

Probado en Linux Mint 22.3 (base Ubuntu 24.04). Otras distribuciones con systemd y `apt` deberían funcionar, pero no están probadas. El origen y el gemelo pueden usar cualquier sistema de archivos en el que Linux pueda escribir (ext4, exFAT, NTFS…).

```bash
git clone https://github.com/<tu-usuario>/disktwin && cd disktwin
cp config.example disktwin.conf
nano disktwin.conf        # UUIDs, punto de montaje del gemelo, discos SMART, usuario, idioma
sudo ./install.sh         # paquetes, comandos, /etc/disktwin.conf, smartd
./install-user.sh         # servicio, cronjob, aviso en la terminal (sin sudo)
```

Para averiguar los datos que pide la configuración:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
ls -l /dev/disk/by-id/ | grep -v -- -part
```

La partición del gemelo tiene que montarse sola al arrancar (con una entrada en `/etc/fstab`) en la ruta de `TARGET_MOUNT`. Si el gemelo es NTFS en Linux Mint, usa el tipo `ntfs-3g`, porque Mint bloquea el driver `ntfs3`:

```
/dev/disk/by-uuid/<UUID> /mnt/twin ntfs-3g nosuid,nodev,nofail,uid=1000,gid=1000,x-gvfs-show 0 0
```

> **La primera copia es larga.** Si son cientos de GB, hazla a mano antes de activar el servicio, para poder ver el progreso: `rsync -rt --info=progress2 ORIGEN/ GEMELO/`. Ten en cuenta que los discos duros SMR (muy comunes en los discos baratos de 2 TB o más) pueden bajar a pocos MB/s en escrituras largas. Es normal; las sincronizaciones del día a día son pequeñas.

## Uso

| Comando | Qué hace |
|---|---|
| `disktwin-sync` | Sincroniza todo ahora |
| `disktwin-sync --force` | Sincroniza todo sin el límite de borrados |
| `disktwin-sync --paths ARCHIVO` | Sincroniza solo las carpetas listadas en el archivo (lo usa el vigilante) |
| `disktwin-alerts` | Lista las alertas pendientes |
| `disktwin-alerts --ok` | Marca todas las alertas como vistas |
| `systemctl --user status disktwin-watch` | Estado del espejo en tiempo real |
| `journalctl --user -u disktwin-watch -f` | Log del vigilante |
| `less ~/.local/state/disktwin/sync.log` | Historial de sincronizaciones |
| `journalctl -u smartmontools` | Log de smartd |
| `sudo smartctl -a /dev/sdX` | Informe SMART completo de un disco |

Los mensajes y avisos siguen `DISKTWIN_LANG` de la configuración: `auto` (según `LANG`), `es` o `en`.

## Archivos

```
bin/disktwin-sync           espejo rsync con las comprobaciones de seguridad
bin/disktwin-watch          vigilante inotify → disktwin-sync --paths (solo lo cambiado)
bin/disktwin-alert          registra una alerta y la notifica (lo usan smartd y el espejo)
bin/disktwin-alerts         muestra y marca como vistas las alertas pendientes
systemd/disktwin-watch.service    servicio de usuario
autostart/disktwin-alerts.desktop recordatorio al iniciar sesión
config.example              plantilla de configuración
install.sh                  instalación como root
install-user.sh             instalación como usuario
```

Dónde queda cada cosa al instalar:

| Qué | Dónde |
|---|---|
| Comandos | `/usr/local/bin/` |
| Configuración | `/etc/disktwin.conf` |
| Configuración de smartd | `/etc/smartd.conf` (el original se guarda en `/etc/smartd.conf.orig`) |
| Alertas | `/var/lib/disktwin/alerts/{pending,seen}` |
| Cronjob | crontab del usuario |

## Lo que disktwin NO es

- **No es RAID.** Si el disco de origen muere, tus datos están a salvo en el gemelo, pero nada cambia de disco automáticamente: el cambio lo haces tú.
- **No es una copia de seguridad.** Es un espejo: un archivo que borras o estropeas en el origen se borra o se estropea en el gemelo a los pocos segundos (solo se frenan los borrados masivos). Combínalo con una copia con historial, como `restic`, `borg` o Timeshift, a ser posible en un tercer sitio: la regla 3-2-1.
- **No es bidireccional.** Los cambios hechos directamente en el gemelo se sobrescriben.
- **No es para el disco del sistema.** Está pensado para discos de datos.
- **No ve la red.** `inotify` solo detecta los cambios hechos desde este ordenador. Si el disco de origen se modifica desde otro equipo, esos cambios los recoge la sincronización completa de cada hora.
- No se copian los permisos ni los propietarios (`rsync -rt`), porque exFAT y NTFS no los guardan como Linux.

## Licencia

[MIT](LICENSE)
