#!/bin/bash

# Configuration
LINUX_SAVES="$HOME/.var/app/com.valvesoftware.Steam/.config/StardewValley/Saves/"
ANDROID_SAVES="/storage/emulated/0/Android/data/com.chucklefish.stardewvalley/files/Saves/"
BACKUP_DIR="$HOME/.cache/stardewValleySync/Backups/"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

echo "--- Stardew Valley Sync ---"

# 0. Check ADB connection
if ! adb get-state 1>/dev/null 2>&1; then
    echo "Erro: Dispositivo Android não encontrado ou não autorizado via ADB."
    echo "Certifique-se de que o Depuramento USB está ativado e que o PC está autorizado."
    exit 1
fi

# 1. Get save lists
linux_list=$(ls "$LINUX_SAVES" 2>/dev/null)
android_list=$(adb shell ls "$ANDROID_SAVES" 2>/dev/null | tr -d '\r')
backup_list=$(ls "$BACKUP_DIR" 2>/dev/null)

# 2. Merge and sort unique names
merged_list=$(echo -e "${linux_list}\n${android_list}" | sort -u | sed '/^$/d')

if [ -z "$merged_list" ]; then
    echo "Nenhum save encontrado no Linux ou Android."
    exit 1
fi

# 3. Present list with numeric IDs
echo "Saves encontrados:"
mapfile -t saves <<< "$merged_list"
for i in "${!saves[@]}"; do
    printf "[%2d] %s\n" "$((i+1))" "${saves[$i]}"
done

# 4. Prompt for save selection
read -p "Escolha o número do save que deseja sincronizar: " save_num

if ! [[ "$save_num" =~ ^[0-9]+$ ]] || [ "$save_num" -lt 1 ] || [ "$save_num" -gt "${#saves[@]}" ]; then
    echo "Opção inválida."
    exit 1
fi

SELECTED_SAVE="${saves[$((save_num-1))]}"
echo "Selecionado: $SELECTED_SAVE"

# 5. Check for existing backup
if [ -d "$BACKUP_DIR/$SELECTED_SAVE" ]; then
    echo ""
    echo "Um backup foi encontrado para este save em $BACKUP_DIR"
    echo "[1] Restaurar backup"
    echo "[2] Usar original (seguir fluxo de sincronização)"
    read -p "Escolha a opção: " backup_option

    if [ "$backup_option" == "1" ]; then
        echo ""
        echo "Para onde deseja restaurar o backup?"
        echo "[1] PC (Linux)"
        echo "[2] Android"
        read -p "Escolha o destino: " restore_dest

        case $restore_dest in
            1)
                echo "Restaurando backup para o PC..."
                cp -r "$BACKUP_DIR/$SELECTED_SAVE" "$LINUX_SAVES"
                ;;
            2)
                echo "Restaurando backup para o Android..."
                adb push "$BACKUP_DIR/$SELECTED_SAVE" "$ANDROID_SAVES"
                ;;
            *)
                echo "Opção inválida."
                exit 1
                ;;
        esac
        echo "Restauração concluída!"
        exit 0
    fi
fi

# 6. Prompt for direction
echo ""
echo "Direção de sincronização:"
echo "[1] PC (Linux) -> Android"
echo "[2] Android -> PC (Linux)"
read -p "Escolha a opção: " direction

case $direction in
    1)
        echo "Sincronizando do PC para o Android..."
        if [ ! -d "$LINUX_SAVES/$SELECTED_SAVE" ]; then
            echo "Erro: Save não encontrado no PC ($LINUX_SAVES/$SELECTED_SAVE)"
            exit 1
        fi
        
        # Backup Android before overwrite
        if adb shell "[ -d \"$ANDROID_SAVES/$SELECTED_SAVE\" ]"; then
            echo "Criando backup do save existente no Android..."
            adb pull "$ANDROID_SAVES/$SELECTED_SAVE" "$BACKUP_DIR"
        fi

        adb push "$LINUX_SAVES/$SELECTED_SAVE" "$ANDROID_SAVES"
        ;;
    2)
        echo "Sincronizando do Android para o PC..."
        # Check if save exists on Android before pulling
        if ! adb shell "[ -d \"$ANDROID_SAVES/$SELECTED_SAVE\" ]"; then
             echo "Erro: Save não encontrado no Android ($ANDROID_SAVES/$SELECTED_SAVE)"
             exit 1
        fi

        # Backup PC before overwrite
        if [ -d "$LINUX_SAVES/$SELECTED_SAVE" ]; then
            echo "Criando backup do save existente no PC..."
            cp -r "$LINUX_SAVES/$SELECTED_SAVE" "$BACKUP_DIR"
        fi

        adb pull "$ANDROID_SAVES/$SELECTED_SAVE" "$LINUX_SAVES"
        ;;
    *)
        echo "Opção inválida."
        exit 1
        ;;
esac

echo "Sincronização concluída!"
