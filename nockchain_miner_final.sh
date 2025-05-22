#!/bin/bash

# === Nockchain Miner Script (Avec menu structuré, transfert, logs, solde) ===

INSTALL_DIR="$HOME/nockchain"
WALLET_DIR="$HOME/.nockchain"
SESSION_NAME="nockmine"
RKEY_FILE="$WALLET_DIR/mining_key.txt"

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

import_wallet_key() {
    mkdir -p "$WALLET_DIR"
    read -p "🔑 Entrez votre clé publique (mining-pubkey): " pubkey
    echo "mining-pubkey $pubkey" > "$RKEY_FILE"
    echo "✅ Clé sauvegardée dans $RKEY_FILE"
}

show_rkey() {
    if [ -f "$RKEY_FILE" ]; then
        echo "🔑 Clé publique actuelle:"
        cat "$RKEY_FILE"
    else
        echo "❌ Aucune clé publique importée."
    fi
}

edit_peers_file() {
    nano "$WALLET_DIR/peers.txt"
}

start_mining_screen() {
    if [ ! -f "$RKEY_FILE" ]; then
        echo "❌ Clé publique non trouvée. Importez-la (option 8)."
        return
    fi
    PUBKEY=$(awk '{print $2}' "$RKEY_FILE")
    [ -f "$WALLET_DIR/peers.txt" ] && peers=$(tr '\n' ' ' < "$WALLET_DIR/peers.txt") || read -p "🧩 Bootnodes (--peer ...): " peers
    rm -rf ./.data.nockchain .socket/nockchain_npc.sock
    screen -S "$SESSION_NAME" -dm bash -c "nockchain --mine --mining-pubkey $PUBKEY $peers | tee -a ~/.nockchain/mining.log; echo '❌ Terminé'; read -n 1"
    echo "✅ Minage lancé dans screen '$SESSION_NAME'"
}

start_mining_autorestart() {
    if [ ! -f "$RKEY_FILE" ]; then echo "❌ Clé manquante." ; return ; fi
    PUBKEY=$(awk '{print $2}' "$RKEY_FILE")
    [ -f "$WALLET_DIR/peers.txt" ] && peers=$(tr '\n' ' ' < "$WALLET_DIR/peers.txt") || read -p "🧩 Bootnodes (--peer ...): " peers
    rm -rf ./.data.nockchain .socket/nockchain_npc.sock
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
    if [ -f "$RKEY_FILE" ]; then
        RKEY=$(awk '{print $2}' "$RKEY_FILE")
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
    echo "5.  🔍 Vérifier état du minage"
    echo "6.  📺 Reprendre session screen"
    echo "7.  ✏️ Éditer les bootnodes (peers.txt)"
    echo ""
    echo "--- Outils Clés ---"
    echo "8.  Importer ma clé publique pour le script"
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
        5) check_screen_status ;;
        6) resume_screen ;;
        7) edit_peers_file ;;
        8) import_wallet_key ;;
        9) show_rkey ;;
        10) export_keys ;;
        11) check_wallet_balance ;;
        12) wallet_transfer ;;
        13) backup_wallet_logs ;;
        14) echo "👋 À bientôt !" ; exit 0 ;;
        *) echo "❌ Choix invalide." ;;
    esac
done
