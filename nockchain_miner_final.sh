
ensure_single_screen() {
    if screen -list | grep -q "\\.$SESSION_NAME"; then
        echo "⚠️ Une session '$SESSION_NAME' est déjà active."
        read -p "🔁 Voulez-vous la fermer avant de relancer ? [o/N] : " confirm
        if [[ "$confirm" =~ ^[oO]$ ]]; then
            screen -S "$SESSION_NAME" -X quit
            echo "🛑 Ancienne session terminée."
        else
            echo "⛔ Lancement annulé."
            return 1
        fi
    fi
    return 0
}

#!/bin/bash

# === Nockchain Miner Script (Avec menu structuré, transfert, logs, solde) ===

INSTALL_DIR="$HOME/nockchain"
WALLET_DIR="$HOME/.nockchain"
SESSION_NAME="nockmine"
ENV_FILE="$INSTALL_DIR/.env"
load_env() {
    if [ -f "$ENV_FILE" ]; then
        export $(grep -v "^#" "$ENV_FILE" | xargs)
        echo "✅ Variables .env chargées."
    else
        echo "⚠️ Fichier .env introuvable à $ENV_FILE"
    fi
}

install_deps() {
    sudo apt update
    sudo apt install -y build-essential curl git clang pkg-config libssl-dev screen
}

install_rust() {
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    rustup update
}

clone_and_build() {
    git clone https://github.com/zorp-corp/nockchain.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    make install-hoonc
    make build
    make install-nockchain
    make install-nockchain-wallet
}

edit_env_file() {
    nano "$ENV_FILE"
}

show_rkey() {
    load_env
    if [ -n "$MINING_PUBKEY" ]; then
        echo "🔑 Clé publique actuelle:"
        echo "$MINING_PUBKEY"
    else
        echo "❌ Aucune clé publique importée."
    fi
}

edit_peers_file() {
    nano "$WALLET_DIR/peers.txt"
}

start_mining_screen() {
    load_env
    if [ -z "$MINING_PUBKEY" ]; then
        echo "❌ Clé publique non trouvée. Importez-la (option 8)."
        return
    fi
    load_env
    PUBKEY="$MINING_PUBKEY"
    [ -f "$WALLET_DIR/peers.txt" ] && peers=$(tr '\n' ' ' < "$WALLET_DIR/peers.txt") || read -p "🧩 Bootnodes (--peer ...): " peers
    rm -rf ./.data.nockchain .socket/nockchain_npc.sock
    ensure_single_screen || return
    screen -S "$SESSION_NAME" -dm bash -c "nockchain --mine --mining-pubkey $PUBKEY $peers | tee -a ~/.nockchain/mining.log; echo '❌ Terminé'; read -n 1"
    echo "✅ Minage lancé dans screen '$SESSION_NAME'"
}

start_mining_autorestart() {
    load_env
    if [ -z "$MINING_PUBKEY" ]; then echo "❌ Clé manquante." ; return ; fi
    load_env
    PUBKEY="$MINING_PUBKEY"
    [ -f "$WALLET_DIR/peers.txt" ] && peers=$(tr '\n' ' ' < "$WALLET_DIR/peers.txt") || read -p "🧩 Bootnodes (--peer ...): " peers
    rm -rf ./.data.nockchain .socket/nockchain_npc.sock
    ensure_single_screen || return
    screen -S "$SESSION_NAME" -dm bash -c '
        while true; do
            echo "[🟢] Lancement à $(date)" | tee -a ~/.nockchain/mining_watchdog.log
            nockchain --mine --mining-pubkey '"$PUBKEY"' '"$peers"' 2>&1 | tee -a ~/.nockchain/mining.log
            echo "[🔴] Arrêt détecté à $(date)" | tee -a ~/.nockchain/mining_watchdog.log
            sleep 10
        done
    '
    echo "✅ Auto-restart actif dans screen '$SESSION_NAME'"
}

start_mining_filtered_logs() {
    load_env
    if [ -z "$MINING_PUBKEY" ]; then
        echo "❌ Clé publique non trouvée. Utilisez l’option 8 pour importer."
        return
    fi
    load_env
    PUBKEY="$MINING_PUBKEY"
    echo "🔍 Minage avec logs filtrés (panic | mining | serf)..."
    rm -rf ./.data.nockchain .socket/nockchain_npc.sock
    nockchain --mine --mining-pubkey "$PUBKEY" | grep -aE "serf|panic|mining"
}

check_screen_status() {
    screen -ls | grep "$SESSION_NAME" && echo "✅ Actif" || echo "❌ Inactif"
}

resume_screen() {
    screen -r "$SESSION_NAME"
}

export_keys() {
    nockchain-wallet export-keys > "$WALLET_DIR/keys.export"
    echo "✅ Export sauvegardé : $WALLET_DIR/keys.export"
}

check_wallet_balance() {
    load_env
    if [ -n "$MINING_PUBKEY" ]; then
        RKEY="$MINING_PUBKEY"
        nockchain-wallet balance --pubkey "$RKEY"
    else
        echo "❌ Clé manquante. Utilisez l'option 8."
    fi
}

wallet_transfer() {
    echo "⚠️ Fonction de transfert expérimentale (si activée dans nockchain-wallet)"
    read -p "Clé publique destinataire : " TO
    read -p "Montant (ex: 1000000000) : " AMOUNT
    nockchain-wallet transfer --to "$TO" --amount "$AMOUNT"
}

backup_wallet_logs() {
    BACKUP_FILE="$HOME/nockchain_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar czf "$BACKUP_FILE" "$WALLET_DIR" 2>/dev/null
    journalctl -u nockchain_autostart > "$HOME/nockchain_logs_$(date +%Y%m%d).log" 2>/dev/null || true
    echo "✅ Sauvegarde complète : $BACKUP_FILE"
}

while true; do
    echo ""
    echo "=== Menu Nockchain Miner ==="
    echo "--- Installation / Mise à Jour ---"
    echo "1.  Installer dépendances"
    echo "2.  Installer Rust"
    echo "3.  Cloner et compiler Nockchain"
    echo ""
    echo "--- Commandes Minage ---"
    echo "4.  🚀 Démarrer le minage dans screen avec bootnodes"
    echo "4a. ♻️ Minage auto-restart avec logs"
	echo "4b. 🔍 Minage avec logs filtrés (serf/panic/mining)"
    echo "5.  🔍 Vérifier état du minage"
    echo "6.  📺 Reprendre session screen"
    echo "7.  ✏️ Éditer les bootnodes (peers.txt)"
    echo ""
    echo "--- Outils Clés ---"
    echo "8.  ✏️ Modifier le fichier .env"
    echo "9.  Voir la clé publique"
    echo "10. 📄 Exporter le wallet (keys.export)"
    echo ""
    echo "--- Wallet ---"
    echo "11. 💰 Voir le solde du portefeuille"
    echo "12. 💸 Transférer des $NOCK"
    echo "13. 💾 Sauvegarder wallet et logs"
    echo "14.  Quitter"
    read -p "Choix : " choix

    case "$choix" in
        1) install_deps ;;
        2) install_rust ;;
        3) clone_and_build ;;
        4) start_mining_screen ;;
        4a) start_mining_autorestart ;;
		4b) start_mining_filtered_logs ;;
        5) check_screen_status ;;
        6) resume_screen ;;
        7) edit_peers_file ;;
        8) edit_env_file ;;
        9) show_rkey ;;
        10) export_keys ;;
        11) check_wallet_balance ;;
        12) wallet_transfer ;;
        13) backup_wallet_logs ;;
        14) echo "👋 À bientôt !" ; exit 0 ;;
        *) echo "❌ Choix invalide." ;;
    esac
done
