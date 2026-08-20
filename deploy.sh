#!/bin/bash
# OLMEICK WooCommerce Bridge — Script de déploiement
# Exécute ce script pour pousser sur GitHub et déployer sur Render

echo "========================================="
echo "  OLMEICK WooCommerce Bridge — Déploiement"
echo "========================================="

# Vérifier que git est installé
if ! command -v git &> /dev/null; then
    echo "❌ Git n'est pas installé. Installe-le depuis https://git-scm.com"
    exit 1
fi

# Créer un repo temporaire
TEMP_DIR=$(mktemp -d)
cp Dockerfile init-mysql.sh start.sh "$TEMP_DIR/"
cd "$TEMP_DIR"

git init
git add .
git commit -m "OLMEICK WooCommerce Bridge - initial"

echo ""
echo "📋 Étapes suivantes :"
echo ""
echo "1. Va sur https://github.com/new"
echo "2. Crée un repo nommé 'olmeick-woocommerce'"
echo "3. Exécute ces commandes :"
echo ""
echo "   git remote add origin https://github.com/TON_UTILISATEUR/olmeick-woocommerce.git"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "4. Va sur https://render.com/new"
echo "5. Clique 'New' → 'Web Service'"
echo "6. Connecte ton repo GitHub 'olmeick-woocommerce'"
echo "7. Render détectera le Dockerfile automatiquement"
echo "8. Clique 'Create Web Service'"
echo ""
echo "Une fois déployé, Render te donnera une URL comme :"
echo "   https://olmeick-woocommerce.onrender.com"
echo ""
echo "9. Va sur https://olmeick-woocommerce.onrender.com/wp-admin"
echo "10. Active WooCommerce et crée les clés API REST"
echo "11. Donne-moi l'URL + Consumer Key + Consumer Secret"
echo ""
echo "========================================="
