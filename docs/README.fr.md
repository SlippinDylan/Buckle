<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Buckle">
  <h1>Buckle</h1>
  <p>Vos outils Mac du quotidien, à portée de clic.</p>
  <p><a href="../README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <strong>Français</strong> · <a href="README.es.md">Español</a></p>
</div>

Buckle est une app macOS native dans la barre des menus : outils système, lancement des navigateurs dans une autre langue et actions Finder courantes. Elle fonctionne en arrière-plan, sans icône dans le Dock.

**[Télécharger pour macOS](https://github.com/SlippinDylan/Buckle/releases/latest)** · [Guide de développement](development.md)

> [!NOTE]
> Ce README décrit le code source actuel. Pour une version téléchargée, consultez ses notes de version pour connaître les changements et les limites.

## Installation et première utilisation

Nécessite **macOS 15 ou ultérieur**, sur Apple Silicon ou Intel. Les compilations CI ciblent Universal 2.

1. Téléchargez `Buckle-<version>.dmg` dans **Assets** de la [dernière version GitHub](https://github.com/SlippinDylan/Buckle/releases/latest). Les archives du code source sont destinées au développement et ne sont pas des installateurs.
2. Pour une mise à jour, choisissez d’abord « Quitter » dans le menu du Buckle en cours et attendez sa fermeture. Ouvrez le DMG et glissez `Buckle.app` dans « Applications », en remplaçant l’ancienne copie si nécessaire.
3. Ouvrez `/Applications/Buckle.app`. Buckle apparaît dans la barre des menus sans icône dans le Dock. Conservez une seule copie installée.
4. Utilisez les outils ou activez les actions Finder dans la barre des menus. Les quatre actions sont désactivées au premier lancement ; vos choix sont ensuite enregistrés.
5. Activez l’extension Finder ou accordez les accès demandés sous **Réglages → Autorisations**. Le statut s’actualise automatiquement ; le texte vert et une coche indiquent un accès accordé ou une extension active.

Le guide de configuration apparaît une seule fois lors d’un lancement normal si vous ne l’avez pas encore fermé ou terminé, y compris pour les utilisateurs existants, dont les réglages sont conservés. Il présente la barre des menus, les actions du Finder et leurs autorisations, le lancement à l’ouverture de session et la recherche automatique de mises à jour. Les modifications sont enregistrées immédiatement. Les quatre actions du Finder restent désactivées tant que vous ne les choisissez pas. Vous pouvez continuer sans autorisation, fermer la fenêtre : le guide ne se rouvre pas automatiquement après un redémarrage ou une mise à niveau. Retrouvez-le sous **Réglages → Général → Afficher le guide de configuration…**. Pour les nouveaux utilisateurs, ignorer le choix des mises à jour laisse la recherche automatique désactivée. Les préférences existantes sont conservées et la recherche manuelle reste disponible dans les versions prenant en charge les mises à jour. La page de fin apparaît dans la même fenêtre ; le bouton pour commencer ouvre le menu de Buckle. Les autorisations figurent sur une page distincte avant les fonctions ; vous pouvez continuer sans les accorder.

> [!IMPORTANT]
> Les compilations utilisent une signature ad hoc et ne sont pas notariées. Une version téléchargée peut nécessiter une autorisation dans Réglages Système ; les accès peuvent devoir être accordés de nouveau après une mise à jour.

L’installation via Homebrew n’est pas encore disponible. Utilisez le DMG jusqu’à la publication du Cask Buckle dans le [Tap commun](https://github.com/SlippinDylan/homebrew-tap).

## Fonctionnalités

<table>
  <tr>
    <td width="36%"><strong>Les outils système dans la barre des menus</strong><br><br>Ouvrez la fenêtre mémoire du système, réinitialisez les utilitaires de souris avec suivi et résultat, ou redémarrez la barre des menus du système. Chaque action Finder peut être activée séparément ; une coche indique son activation.</td>
    <td width="64%" align="center"><img src="images/readme/menu-bar.png" width="310" alt="Les outils système dans la barre des menus"></td>
  </tr>
  <tr>
    <td width="36%"><strong>Agir directement dans le Finder</strong><br><br>Ajoutez AirDrop, Ouvrir dans Terminal, Copier le chemin et Déplacer les éléments ici au menu contextuel du Finder. Terminal s’ouvre dans le dossier sélectionné ou courant ; les chemins multiples sont copiés sur des lignes distinctes.</td>
    <td width="64%" align="center"><img src="images/readme/finder-context-menu.png" width="285" alt="Agir directement dans le Finder"></td>
  </tr>
  <tr>
    <td width="36%"><strong>Lancer les navigateurs dans huit langues</strong><br><br>Choisissez un navigateur installé, puis une langue. Buckle détecte les navigateurs pris en charge à chaque ouverture du menu. Le lancement est réalisé directement par l’app, sans script personnel.</td>
    <td width="64%" align="center"><img src="images/readme/browser-language.png" width="580" alt="Lancer les navigateurs dans huit langues"></td>
  </tr>
</table>

## Réglages

Gérez le lancement à l’ouverture de session et la langue dans **Réglages → Général**. Par défaut, l’interface suit macOS. Vous pouvez choisir l’anglais, le chinois simplifié ou traditionnel, le japonais, le coréen, l’allemand, le français ou l’espagnol. Redémarrez Buckle pour appliquer un changement de langue.

Sous **Réglages → Réinitialisation**, ajoutez ou retirez des apps et réglez le délai avant leur réouverture de 0 à 60 secondes, avec 3 secondes par défaut. Les changements sont enregistrés automatiquement ; la modification est désactivée pendant une réinitialisation.

<p align="center">
  <img src="images/readme/general-settings.png" width="340" alt="Réglages généraux">
  <img src="images/readme/permissions-settings.png" width="340" alt="État des autorisations">
</p>

Les captures présentent l’interface anglaise et peuvent différer de votre version installée. Les menus dépendent des navigateurs, des actions activées et des fichiers copiés.

## À savoir avant utilisation

- **Fenêtre mémoire :** ouvre manuellement macOS LowMemoryPanel, même avec une utilisation mémoire normale. Son avertissement intégré n’est pas un diagnostic de Buckle. Cette fonction utilise un chemin de débogage privé du système. Buckle vérifie la fenêtre d’avertissement mémoire, restaure le réglage temporaire et signale un échec si la fenêtre ne peut pas être confirmée. La compatibilité doit être testée sur chaque version de macOS. Les autorisations Accessibilité et Automatisation de System Events sont nécessaires ; aucune surveillance en arrière-plan.
- **Réinitialiser la souris :** gérez la liste dans **Réglages → Réinitialisation**. Elle contient initialement Moom, MonitorControl, BetterMouse et iShot Pro. Chaque opération ferme les applications actives de la liste, actualise les services partagés de préférences et d’autorisations système de macOS, puis rouvre ces applications. Seules les applications déjà actives sont rouvertes. L’actualisation des services peut affecter brièvement d’autres applications et nécessite une autorisation administrateur. Les apps désinstallées sont ignorées ; les services sont actualisés même si la liste est vide. La liste des apps à rouvrir est enregistrée. Après une interruption, Buckle propose de les rouvrir au prochain lancement ; choisir « Plus tard » conserve cet enregistrement.
- **Redémarrer la barre des menus :** relance le SystemUIServer de votre session sans sudo. Cela ne corrige pas forcément les icônes gérées par d’autres apps.
- **Profils de navigateur :** utilise les données existantes et les connexions enregistrées du navigateur, sans créer de profil distinct. Le choix entre plusieurs profils suit le comportement du navigateur. Quittez le navigateur avant de changer sa langue de lancement. S’il est déjà ouvert, Buckle affiche seulement un message. Le lancement en japonais demande le fuseau horaire de Tokyo pour le processus du navigateur, comme le script d’origine ; les autres langues conservent le fuseau du système. Les réglages macOS et l’adresse IP ne changent pas. La langue et les formats régionaux des sites ne sont pas garantis. Le comportement du fuseau horaire a été vérifié uniquement avec Chrome Beta.
- **Finder :** l’extension copie les chemins en texte brut, un chemin par ligne ; les autres actions lancent Buckle au besoin. Pour déplacer des fichiers, copiez-les dans le Finder, puis faites un clic droit sur le dossier cible ou son arrière-plan. Buckle ouvre ce dossier dans le Finder et déclenche sa commande native de déplacement. Les autorisations Accessibilité et Automatisation pour Finder et System Events sont nécessaires. Le Finder gère la progression, les conflits de noms et l’annulation ; consultez ses dialogues pour connaître le résultat. Buckle n’attend pas la fin du transfert. Le Finder détermine la position du menu. Les libellés Finder propres à Buckle suivent la langue de l’app après son redémarrage ; le nom AirDrop natif suit le système. La page des autorisations affiche séparément les accès d’automatisation au Finder et à System Events. Si les raccourcis de menu du Finder ou globaux sont personnalisés, le déplacement automatique est désactivé pour éviter d’exécuter une autre commande. Utilisez alors directement le Finder.
- **AirDrop :** ouvre l’interface de partage du système sans attendre la fin du transfert. Une seule session AirDrop peut être ouverte à la fois ; les autres actions du Finder restent disponibles. Buckle ne retarde pas sa fermeture pour AirDrop ; laissez-le ouvert pendant l’utilisation de la fenêtre de partage.
- **Mises à jour :** Sparkle est intégré. La vérification manuelle se trouve dans **Réglages → À propos**, et la vérification automatique dans **Général**. Les versions de développement, les validations CI et les paquets de test désactivent les mises à jour ; les versions officielles Release les activent. Lorsque la création de paquets est activée, une compilation CI complète réussie sur main crée et publie automatiquement une version encore inédite, puis synchronise le flux signé et le Cask Homebrew. Les modifications limitées à la documentation ou aux fichiers auxiliaires ne publient rien. Les mises à jour en ligne nécessitent un installateur publié et un flux signé.

## Compiler depuis les sources

<details>
<summary>Afficher les étapes de compilation et de développement</summary>

Nécessite Xcode 26 ou ultérieur, Node.js et Python 3. Aucun compte développeur Apple n’est nécessaire en Debug.

```bash
git clone https://github.com/SlippinDylan/Buckle.git
cd Buckle
bash Scripts/check.sh
bash Scripts/build.sh Debug
```

Après la compilation, choisissez l’une des deux méthodes suivantes.

### Installer pour une utilisation quotidienne

Quittez Buckle avec **Quitter** dans son menu de la barre des menus et attendez sa fermeture. Dans le Finder, déplacez l’intégralité de `Buckle.app` depuis `build/DerivedData/Build/Products/Debug/` vers `/Applications`. Pour remplacer une copie existante, quittez-la d’abord. Ouvrez `/Applications/Buckle.app` et conservez une seule copie installée.

### Exécuter pour le développement

Fermez tout Buckle en cours avec **Quitter** et attendez sa fermeture avant d’exécuter la commande ci-dessous. Vous pouvez aussi ouvrir ensuite `Buckle.xcodeproj` et exécuter le scheme `Buckle` en Debug. Buckle n’autorise qu’une instance à la fois : le nouveau processus se ferme si une autre copie est encore active. Pendant le développement, utilisez la compilation à tester sans ouvrir simultanément la copie installée.

```bash
open build/DerivedData/Build/Products/Debug/Buckle.app
```

</details>

## Documentation de développement

Le [guide de développement](development.md) (en chinois) couvre l’architecture, les vérifications, les paquets CI, les mises à jour, la signature et les tests sur Mac. Les installateurs publiés se trouvent dans [GitHub Releases](https://github.com/SlippinDylan/Buckle/releases) ; les [notes de version](../CHANGELOG.md) sont rédigées en anglais.
