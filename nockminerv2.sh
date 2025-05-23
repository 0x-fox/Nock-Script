#!/bin/bash

# === FoX $NOCK MiNeR ===

BASE_DIR="$HOME/nockchain"
MINER_DIR="$HOME/.nockminers"
PEERS_FILE="$MINER_DIR/peers.txt"
ENV_FILE="$BASE_DIR/.env"
PORT_BASE=30333

mkdir -p "$MINER_DIR"
touch "$PEERS_FILE"

logo() {
    cat << "EOF"
 _____   __  __   _  _   _  ___   ____ _  __  __  __ _ _   _      ____   
|  ___|__\ \/ /  | || \ | |/ _ \ / ___| |/ / |  \/  (_) \ | | ___|  _ \  
| |_ / _ \\  /  / __)  \| | | | | |   | ' /  | |\/| | |  \| |/ _ \ |_) | 
|  _| (_) /  \  \__ \ |\  | |_| | |___| . \  | |  | | | |\  |  __/  _ <  
|_|  \___/_/\_\ (   /_| \_|\___/ \____|_|\_\ |_|  |_|_|_| \_|\___|_| \_\ 
                 |_|                                                     
                            FoX $NOCK MiNeR V2
EOF
}

get_next_port() {
    existing=$(ls "$BASE_DIR" | grep -E '^miner[0-9]+' | wc -l)
    echo $((PORT_BASE + existing))
}


get_next_miner_name() {
    local i=1
    while [[ -d "$BASE_DIR/miner$i" ]]; do
        ((i++))
    done
    echo "miner$i"
}

start_miner() {
    NAME=$(get_next_miner_name)
    DIR="$BASE_DIR/$NAME"
    mkdir -p "$DIR"

    PORT=$(get_next_port)
    echo "$PORT" > "$DIR/port.txt"

    PUBKEY=$(grep '^MINING_PUBKEY=' "$ENV_FILE" | cut -d '=' -f2)

    CMD="cd $DIR && RUST_LOG=info,nockchain=info MINIMAL_LOG_FORMAT=true $HOME/.cargo/bin/nockchain --mine --mining-pubkey $PUBKEY "
    if [ -s "$PEERS_FILE" ]; then
        while read -r peer; do CMD+=" --peer $peer"; done < "$PEERS_FILE"
    fi

    # Copy .env to ensure local context if needed
    cp "$ENV_FILE" "$DIR/.env"

    # Launch screen in correct working directory
    screen -S "$NAME" -dm bash -c "cd $DIR && exec bash -c '$CMD; exec bash'"
    echo "[✅] Mineur '$NAME' lancé automatiquement sur le port $PORT."
}

show_logs() {
  echo "[📋] Mineurs actifs (screen) :"
  mapfile -t MINERS < <(screen -ls | grep -oE "[0-9]+\.miner[0-9]+" | cut -d. -f2)
  if [ ${#MINERS[@]} -eq 0 ]; then echo "Aucun mineur actif."; return; fi
  for i in "${!MINERS[@]}"; do echo "$((i+1)). ${MINERS[$i]}"; done
  read -rp "Choisir un mineur (1-${#MINERS[@]}) : " CHOICE
  if [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#MINERS[@]} )); then
    NAME="${MINERS[$((CHOICE-1))]}"
    session_info=$(screen -ls | grep "\\.$NAME")
    echo "[📋] Session détectée : $session_info"
    if echo "$session_info" | grep -q "Detached"; then
      echo "[🔁] Ouverture avec screen -r (détaché)"
      screen -r "$NAME"
    else
      echo "[👥] Ouverture avec screen -x (déjà attaché)"
      screen -x "$NAME"
    fi
  else
    echo "[❌] Choix invalide."
  fi
}


list_miners() {
  echo "[📋] Mineurs actifs (screen) :"
  screen -ls | grep -oE '[0-9]+\.miner[0-9]+' | cut -d. -f2 || echo "Aucun mineur actif."
}
restart_miner() {
    read -rp "Nom du mineur à redémarrer : " NAME
    DIR="$BASE_DIR/$NAME"
    cd "$DIR" || exit
    if screen -list | grep -q "$NAME"; then screen -XS "$NAME" quit; fi
    rm -rf ./.data.nockchain .socket
    PORT=$(cat "$DIR/port.txt")
    PUBKEY=$(grep '^MINING_PUBKEY=' "$ENV_FILE" | cut -d '=' -f2)
    CMD="cd $DIR && RUST_LOG=info,nockchain=info MINIMAL_LOG_FORMAT=true $HOME/.cargo/bin/nockchain --mine --mining-pubkey $PUBKEY "
    if [ -s "$PEERS_FILE" ]; then
        while read -r peer; do CMD+=" --peer $peer"; done < "$PEERS_FILE"
    fi
    screen -S "$NAME" -dm bash -c "cd $MINER_DIR && exec bash -c '$CMD; exec bash'"
    screen -S "$NAME" -X logfile $MINER_DIR/screen.log
    screen -S "$NAME" -X log on
    echo "[🔄] Mineur '$NAME' redémarré."
}

stop_miner() {
    read -rp "Nom du mineur à arrêter : " NAME
    screen -XS "$NAME" quit
    echo "[🛑] Mineur '$NAME' arrêté."
}

generate_wallet_key() {
    cd "$BASE_DIR" || exit
    source "$HOME/.cargo/env"
    mkdir -p "$BASE_DIR/wallet_backup"

    echo "[🔐] Génération d'une nouvelle clé wallet..."
    nockchain-wallet keygen | tee "$BASE_DIR/wallet_backup/generated_keys.txt"

    PUBKEY=$(grep --text "Public Key" "$BASE_DIR/wallet_backup/generated_keys.txt" | head -n1 | awk '{print $NF}')
    if [ -n "$PUBKEY" ]; then
        echo "[🔄] Remplacement de MINING_PUBKEY dans .env avec : $PUBKEY"
        sed -i "/^MINING_PUBKEY=/c\MINING_PUBKEY=$PUBKEY" "$ENV_FILE"
        echo "[✅] MINING_PUBKEY mis à jour dans .env"
    else
        echo "[❌] Clé publique introuvable. Vérifie le fichier generated_keys.txt"
    fi
}


reset_miners() {
  echo "[⚠️] Cette opération va supprimer tous les dossiers minerX et redémarrer la numérotation à miner1."
  read -rp "Confirmer ? (oui/non) : " CONFIRM
  if [[ "$CONFIRM" == "oui" ]]; then
    find "$BASE_DIR" -maxdepth 1 -type d -name "miner*" -exec rm -rf {} +
    echo "[🧹] Réinitialisation terminée."
  else
    echo "[🚫] Opération annulée."
  fi
}

main_menu() {
    clear
    logo
    echo "=== Menu Nockchain Miner ==="
    echo "--- Installation / Mise à Jour ---"
    echo " 1. Installer dépendances"
    echo " 2. Installer Rust"
    echo " 3. Cloner et compiler Nockchain"
    echo ""
    echo "--- Commandes Minage ---"
    echo " 4. Démarrer un mineur"
    echo " 5. Logs live d'un mineur"
    echo " 6. État des mineurs"
    echo " 7. Relancer un mineur"
    echo " 8. Arrêter un mineur"
    echo ""
    echo "--- Config ---"
    echo " 9. Éditer .env"
    echo "10. Éditer les bootnodes (peers.txt)"
    echo ""
    echo "--- Wallet ---"
    echo "11. Voir infos wallet (à venir)"
    echo "12. Transférer des jetons (à venir)"
    echo "13. Sauvegarder wallet et logs (à venir)"
    echo "15. Créer une nouvelle clé wallet (keygen)"
    echo ""
echo "14. Quitter"
    echo "16. Réinitialiser tous les mineurs (miner1, miner2...)"
    echo ""
    read -rp "Choix : " choix
}

while true; do
    main_menu
    case "$choix" in
        1) sudo apt update && sudo apt upgrade -y && sudo apt install curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libclang-dev llvm-dev screen -y ;;
        2) curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && source "$HOME/.cargo/env" && echo 'source "$HOME/.cargo/env"' >> "$HOME/.bashrc" ;;
        3) rm -rf "$BASE_DIR" && git clone https://github.com/zorp-corp/nockchain "$BASE_DIR" && cd "$BASE_DIR" && cp .env_example .env && make install-hoonc && make build && make install-nockchain-wallet && make install-nockchain && echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc" ;;
        4) start_miner ;;
        5) show_logs ;;
        6) list_miners ;;
        7) restart_miner ;;
        8) stop_miner ;;
        9) nano "$ENV_FILE" ;;
       10) nano "$PEERS_FILE" ;;
       15) generate_wallet_key ;;
14) echo "Bye 👋" && exit 0 ;;
        16) reset_miners ;;        *) echo "Option invalide." && sleep 1 ;;
    esac
    read -n 1 -s -r -p "Appuie sur une touche pour revenir au menu..."
done

}
