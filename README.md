# MoneyK1000

Application mobile de suivi de compte : on note ses recettes et ses dépenses, et on connaît à tout moment son solde réel et son solde prévisionnel à une date donnée.

Projet personnel, écrit en Flutter, pour Android.

## Fonctionnement

L'écran unique affiche trois montants :

- **Solde** — le solde de référence, modifiable à la main (icône crayon). C'est ce que dit le relevé de banque.
- **Après opérations cochées** — n'apparaît que si au moins une case est cochée. Le solde de référence augmenté des opérations pointées. En lecture seule.
- **Solde au jj/mm** — en bas de l'écran. Le solde prévisionnel à la date choisie, qui intègre toutes les opérations non cochées jusqu'à cette date.

Chaque opération de la liste porte :

| Élément | Rôle |
|---|---|
| Date | jour et mois de l'opération |
| Libellé | intitulé libre |
| ✏️ | rouvrir le formulaire pour modifier |
| 🔄 | comptabiliser le montant sur le solde et reporter la ligne au même jour du mois suivant |
| ❌ | supprimer, avec le choix de comptabiliser le montant au passage |
| Montant | rouge si dépense, vert si recette |
| ☑️ | pointer l'opération |

Quand au moins une case est cochée, les icônes de report et de suppression groupés apparaissent à côté du solde et s'appliquent à toutes les lignes pointées.

Les opérations sont triées par date, avec un trait de séparation entre deux mois.

## Choix techniques

- **Les montants sont stockés en centimes entiers** (`int`), jamais en `double`. En virgule flottante, `0.1 + 0.2` ne vaut pas `0.3` ; sur des centaines d'opérations cela produit des écarts de centimes impossibles à expliquer. La division par 100 n'a lieu qu'à l'affichage.
- **Les dates sont ramenées à minuit** à la saisie comme au chargement, et la projection est bornée à 23h59 du jour choisi. Sans cela, une opération enregistrée aujourd'hui à 14h serait jugée postérieure à « aujourd'hui » et exclue du calcul.
- **Pas de catégories** : choix assumé, l'appli répond à la question « combien me reste-t-il », pas « où part mon argent ».
- **Recettes et dépenses dans une seule liste**, distinguées par le signe du montant, comme un relevé bancaire.
- **Persistance par `shared_preferences`** (JSON). Suffisant pour quelques centaines d'opérations ; à remplacer par SQLite au-delà.

## Lancer le projet

```bash
flutter pub get
flutter devices          # repérer l'appareil cible
flutter run -d <appareil>
```

Pendant l'exécution, dans le terminal : `r` recharge à chaud, `R` redémarre, `q` quitte.

Régénérer les icônes de lanceur après modification de `assets/icon/icon.png` :

```bash
dart run flutter_launcher_icons
```

## Structure

```
lib/main.dart          toute l'application
assets/icon/icon.png   source de l'icône de lanceur
```

Le projet tient volontairement dans un seul fichier à ce stade.

## À faire

- Tests unitaires sur les trois calculs de solde
- Découper `main.dart` : interface, état, persistance, logique métier
- Passage à SQLite si le volume d'opérations le justifie
- Build release signé
