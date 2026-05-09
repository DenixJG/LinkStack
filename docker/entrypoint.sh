#!/bin/bash
set -e

echo "==> Iniciando LinkStack (entorno local)..."

# --- Permisos de escritura ---
echo "==> Ajustando permisos..."
chown -R www-data:www-data storage bootstrap/cache 2>/dev/null || true
chmod -R 775 storage bootstrap/cache 2>/dev/null || true

# --- Composer install si no existe vendor ---
if [ ! -d "vendor" ] || [ ! -f "vendor/autoload.php" ]; then
    echo "==> Ejecutando composer install..."
    composer install --no-interaction --prefer-dist
fi

# --- Generar APP_KEY si no esta definido ---
if grep -q "^APP_KEY=$" .env 2>/dev/null || ! grep -q "^APP_KEY=" .env 2>/dev/null; then
    echo "==> Generando APP_KEY..."
    php artisan key:generate --force
fi

# --- Esperar a que MySQL este listo ---
echo "==> Esperando conexion con MySQL (${DB_HOST}:${DB_PORT:-3306})..."
MAX_TRIES=30
COUNT=0
until php -r "
    try {
        \$pdo = new PDO(
            'mysql:host=${DB_HOST};port=${DB_PORT:-3306};dbname=${DB_DATABASE}',
            '${DB_USERNAME}',
            '${DB_PASSWORD}'
        );
        exit(0);
    } catch (Exception \$e) {
        exit(1);
    }
" 2>/dev/null; do
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_TRIES ]; then
        echo "ERROR: MySQL no respondio despues de ${MAX_TRIES} intentos. Abortando."
        exit 1
    fi
    echo "  MySQL no disponible aun, reintentando ($COUNT/$MAX_TRIES)..."
    sleep 2
done
echo "==> MySQL listo."

# --- Migraciones ---
echo "==> Ejecutando migraciones..."
php artisan migrate --force

# --- Marcar como instalado (LinkStack lo requiere) ---
if [ ! -f "storage/app/ISINSTALLED" ]; then
    echo "==> Marcando instalacion..."
    touch storage/app/ISINSTALLED
fi

echo "==> Aplicacion lista."
exec "$@"
