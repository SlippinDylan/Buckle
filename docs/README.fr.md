<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Buckle">
  <h1>Buckle</h1>
  <p>Vos outils Mac du quotidien, à portée de clic.</p>
  <p><a href="../README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <strong>Français</strong> · <a href="README.es.md">Español</a></p>
</div>

Buckle est une app macOS native dans la barre des menus : outils système, lancement des navigateurs dans une autre langue et actions Finder courantes. Elle fonctionne en arrière-plan, sans icône dans le Dock.

> [!NOTE]
> Buckle 0.1.1 ne dispose pas encore de programme d’installation public. Suivez les instructions de compilation ci-dessous.

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

### Réglages

Gérez le lancement à l’ouverture de session et la langue dans **Réglages → Général**. Par défaut, l’interface suit macOS. Vous pouvez choisir l’anglais, le chinois simplifié ou traditionnel, le japonais, le coréen, l’allemand, le français ou l’espagnol. Redémarrez Buckle pour appliquer un changement de langue.

<p align="center">
  <img src="images/readme/general-settings.png" width="340" alt="Réglages généraux">
  <img src="images/readme/permissions-settings.png" width="340" alt="État des autorisations">
</p>

Les captures montrent l’interface en anglais. Les menus dépendent des navigateurs installés, des actions activées et des fichiers copiés.

## Installation et première utilisation

Nécessite **macOS 15 ou ultérieur**, sur Apple Silicon ou Intel. Les compilations CI ciblent Universal 2.

1. Suivez les étapes de compilation et d’installation ci-dessous, puis ouvrez l’app installée dans `/Applications`.
2. Cliquez sur l’icône de la barre des menus pour utiliser un outil ou activer une action Finder. Les quatre actions Finder sont désactivées au départ ; vos choix sont ensuite conservés.
3. Ouvrez **Réglages → Autorisations** pour activer l’extension Finder ou accorder les accès demandés. L’état s’actualise automatiquement ; le texte vert et la coche indiquent un accès accordé ou une extension activée.

Les compilations utilisent une signature ad hoc et ne sont pas notariées. Une version téléchargée peut nécessiter une autorisation dans Réglages Système ; les accès peuvent devoir être accordés de nouveau après une mise à jour.

## À savoir avant utilisation

- **Fenêtre mémoire :** ouvre manuellement macOS LowMemoryPanel, même avec une utilisation mémoire normale. Son avertissement intégré n’est pas un diagnostic de Buckle. Cette fonction utilise un chemin de débogage privé du système. Buckle vérifie la fenêtre d’avertissement mémoire, restaure le réglage temporaire et signale un échec si la fenêtre ne peut pas être confirmée. La compatibilité doit être testée sur chaque version de macOS. Les autorisations Accessibilité et Automatisation de System Events sont nécessaires ; aucune surveillance en arrière-plan.
- **Réinitialiser la souris :** gérez la liste dans **Réglages → Réinitialisation**. Elle contient initialement Moom, MonitorControl, BetterMouse et iShot Pro. Chaque opération ferme les applications actives de la liste, actualise les services partagés de préférences et d’autorisations système de macOS, puis rouvre ces applications. Seules les applications déjà actives sont rouvertes. L’actualisation des services peut affecter brièvement d’autres applications et nécessite une autorisation administrateur. Les apps désinstallées sont ignorées ; les services sont actualisés même si la liste est vide. La liste des apps à rouvrir est enregistrée. Après une interruption, Buckle propose de les rouvrir au prochain lancement ; choisir « Plus tard » conserve cet enregistrement.
- **Redémarrer la barre des menus :** relance le SystemUIServer de votre session sans sudo. Cela ne corrige pas forcément les icônes gérées par d’autres apps.
- **Profils de navigateur :** utilise les données existantes et les connexions enregistrées du navigateur, sans créer de profil distinct. Le choix entre plusieurs profils suit le comportement du navigateur. Quittez le navigateur avant de changer sa langue de lancement. S’il est déjà ouvert, Buckle affiche seulement un message. L’adresse IP et le fuseau horaire ne changent pas, et la langue des sites n’est pas garantie.
- **Finder :** la copie des chemins est effectuée dans l’extension ; les autres actions lancent Buckle au besoin. Pour déplacer des fichiers, copiez-les dans le Finder, puis faites un clic droit sur le dossier cible ou son arrière-plan. Le déplacement demande confirmation, ne remplace aucun élément existant et n’est pas intégré à l’annulation du Finder. En cas d’échec partiel, les déplacements terminés sont conservés : vérifiez les deux dossiers avant de réessayer. Le Finder détermine la position du menu. Les libellés Finder propres à Buckle suivent la langue de l’app après son redémarrage ; le nom AirDrop natif suit le système.
- **Mises à jour :** Sparkle est intégré. La vérification manuelle se trouve dans **Réglages → À propos**, et la vérification automatique dans **Général**. Les versions de développement et de pull request désactivent les mises à jour ; les versions de publication CI sur main les activent. Les mises à jour en ligne nécessitent un programme d’installation publié et un flux signé.

## Compiler depuis les sources

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

## Documentation de développement

Le [guide de développement](development.md) (chinois simplifié) détaille les vérifications, la CI, les paquets, la publication des mises à jour, la signature et la validation sur Mac. Les futurs programmes d’installation seront publiés sur [GitHub Releases](https://github.com/SlippinDylan/Buckle/releases).
