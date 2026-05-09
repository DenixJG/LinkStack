# LinkStack - Entorno de desarrollo local con Docker

Este documento describe como levantar, usar y mantener el entorno de desarrollo
local de LinkStack usando Docker y `compose.local.yml`.

## Requisitos previos

- Windows 10/11 con Docker Desktop instalado y en ejecucion
- Git (para clonar el repositorio)
- No es necesario tener PHP, Composer ni Node.js instalados en el host

## Estructura de archivos Docker

```
linkstack/
  Dockerfile                   Imagen PHP 8.2-FPM con Composer y Node.js 20
  compose.local.yml            Definicion de servicios para desarrollo local
  .env.docker                  Plantilla de variables de entorno para Docker
  .dockerignore                Archivos excluidos del contexto de build
  docker/
    entrypoint.sh              Script de inicio (permisos, migraciones, etc.)
    nginx/
      default.conf             Configuracion de Nginx para Laravel
```

## Servicios

| Servicio    | Imagen               | Puerto local       | Descripcion                              |
|-------------|----------------------|--------------------|------------------------------------------|
| `app`       | Dockerfile local     | (interno, 9000)    | PHP 8.2-FPM con la aplicacion Laravel    |
| `nginx`     | nginx:1.25-alpine    | 8080               | Web server, sirve el frontend            |
| `mysql`     | mysql:8.0            | 3306               | Base de datos principal                  |
| `redis`     | redis:7-alpine       | 6379               | Cache y sesiones (opcional)              |
| `mailhog`   | mailhog/mailhog      | 8025 (UI), 1025    | Captura de correos salientes             |

URLs disponibles una vez levantado el entorno:

- Aplicacion: http://localhost:8080
- Mailhog (bandeja de entrada local): http://localhost:8025
- MySQL accesible en `localhost:3306` desde clientes como DBeaver o TablePlus

---

## Primer arranque

### 1. Copiar el archivo de entorno

```powershell
Copy-Item .env.docker .env
```

Edita `.env` si necesitas cambiar valores (app key, nombre de la BD, etc.).
El campo `APP_KEY` se genera automaticamente en el primer arranque.

### 2. Construir la imagen

La primera vez descarga dependencias del sistema, Composer y Node.js.
Puede tardar entre 3 y 8 minutos segun la conexion.

```powershell
docker compose -f compose.local.yml build
```

### 3. Levantar todos los servicios

```powershell
docker compose -f compose.local.yml up -d
```

El contenedor `app` ejecuta automaticamente al iniciarse:

1. Ajuste de permisos en `storage/` y `bootstrap/cache/`
2. `composer install` si la carpeta `vendor/` no existe
3. Generacion de `APP_KEY` si el `.env` lo tiene vacio
4. Espera activa hasta que MySQL responda (hasta 60 segundos)
5. `php artisan migrate`
6. Creacion del archivo `storage/app/ISINSTALLED` requerido por LinkStack

### 4. Verificar que todo este corriendo

```powershell
docker compose -f compose.local.yml ps
```

Todos los servicios deben aparecer con estado `running`.
Para ver los logs del arranque de la aplicacion:

```powershell
docker compose -f compose.local.yml logs -f app
```

---

## Uso diario

### Iniciar los servicios

```powershell
docker compose -f compose.local.yml up -d
```

### Detener los servicios (mantiene los datos)

```powershell
docker compose -f compose.local.yml down
```

### Ver logs en tiempo real

```powershell
# Todos los servicios
docker compose -f compose.local.yml logs -f

# Solo la aplicacion PHP
docker compose -f compose.local.yml logs -f app

# Solo Nginx
docker compose -f compose.local.yml logs -f nginx
```

---

## Comandos Artisan

Todos los comandos de Artisan se ejecutan dentro del contenedor `app`:

```powershell
# Forma general
docker compose -f compose.local.yml exec app php artisan <comando>

# Ejemplos
docker compose -f compose.local.yml exec app php artisan migrate
docker compose -f compose.local.yml exec app php artisan migrate:fresh --seed
docker compose -f compose.local.yml exec app php artisan cache:clear
docker compose -f compose.local.yml exec app php artisan config:clear
docker compose -f compose.local.yml exec app php artisan route:list
docker compose -f compose.local.yml exec app php artisan tinker
```

---

## Compilacion de assets (Laravel Mix)

El contenedor `app` incluye Node.js 20 y npm. Los assets se compilan dentro
del contenedor para evitar incompatibilidades entre el host Windows y Linux.

```powershell
# Instalar dependencias npm (solo la primera vez o al cambiar package.json)
docker compose -f compose.local.yml exec app npm install

# Compilar para desarrollo (una sola vez)
docker compose -f compose.local.yml exec app npm run dev

# Watcher (recompila al guardar cambios en recursos JS/CSS)
docker compose -f compose.local.yml exec app npm run watch
```

---

## Abrir una shell en el contenedor

```powershell
docker compose -f compose.local.yml exec app bash
```

Desde ahi puedes ejecutar cualquier comando como si estuvieras en el servidor.

---

## Base de datos

### Credenciales locales

| Parametro | Valor      |
|-----------|------------|
| Host      | `localhost` (desde el host) / `mysql` (desde otros contenedores) |
| Puerto    | `3306`     |
| Base      | `linkstack` |
| Usuario   | `linkstack` |
| Password  | `secret`   |
| Root pass | `secret`   |

### Conectar con un cliente externo (DBeaver, TablePlus, etc.)

Usa `localhost:3306` con el usuario y password de la tabla anterior.

### Acceder via consola MySQL dentro del contenedor

```powershell
docker compose -f compose.local.yml exec mysql mysql -u linkstack -psecret linkstack
```

### Recrear la base de datos desde cero

```powershell
# Elimina el volumen y re-ejecuta las migraciones
docker compose -f compose.local.yml down -v
docker compose -f compose.local.yml up -d
```

---

## Correo electronico (Mailhog)

Mailhog intercepta todos los correos enviados por la aplicacion sin enviarlos
realmente. Util para probar flujos de registro, recuperacion de password, etc.

- Bandeja de entrada: http://localhost:8025
- La configuracion en `.env.docker` ya apunta a Mailhog por defecto

---

## Cambiar cache y sesiones a Redis

Por defecto la aplicacion usa el driver `file` para cache y sesiones.
Para cambiar a Redis edita `.env`:

```dotenv
CACHE_DRIVER=redis
SESSION_DRIVER=redis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379
```

Luego limpia la cache:

```powershell
docker compose -f compose.local.yml exec app php artisan cache:clear
docker compose -f compose.local.yml exec app php artisan config:clear
```

---

## Reconstruir la imagen

Necesario cuando cambias el `Dockerfile`, instalas nuevas extensiones PHP o
actualizas dependencias del sistema:

```powershell
docker compose -f compose.local.yml build --no-cache
docker compose -f compose.local.yml up -d
```

---

## Problemas frecuentes

### La aplicacion muestra un error 500 en el primer arranque

Espera a que el entrypoint termine. Revisa los logs:

```powershell
docker compose -f compose.local.yml logs -f app
```

Si el problema persiste, regenera la key y limpia cache:

```powershell
docker compose -f compose.local.yml exec app php artisan key:generate
docker compose -f compose.local.yml exec app php artisan config:clear
docker compose -f compose.local.yml exec app php artisan cache:clear
```

### MySQL tarda en estar listo

El entrypoint espera hasta 60 segundos. Si MySQL sigue sin responder,
aumenta `start_period` en el healthcheck de `compose.local.yml` o revisa
si hay otro proceso usando el puerto 3306 en el host:

```powershell
netstat -ano | findstr :3306
```

### Permisos denegados en storage/

```powershell
docker compose -f compose.local.yml exec app chmod -R 775 storage bootstrap/cache
docker compose -f compose.local.yml exec app chown -R www-data:www-data storage bootstrap/cache
```

### El watcher de Mix no detecta cambios en Windows

Usa el modo polling en lugar del watcher de sistema de archivos:

```powershell
docker compose -f compose.local.yml exec app npm run watch-poll
```

---

## Limpiar el entorno completamente

Elimina contenedores, imagenes creadas localmente y el volumen de MySQL.
**Los datos de la base de datos se pierden.**

```powershell
docker compose -f compose.local.yml down -v --rmi local
```
