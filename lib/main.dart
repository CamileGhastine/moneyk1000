import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MoneyK1000App());
}

// Les montants sont stockés en CENTIMES ENTIERS, jamais en double :
// 0.1 + 0.2 ne vaut pas 0.3 en virgule flottante, et sur des centaines
// d'opérations cela produit des écarts de centimes inexplicables.
// La division par 100 n'a lieu qu'à l'affichage.
String formaterMontant(int centimes) => (centimes / 100).toStringAsFixed(2);

// Ramène une date à minuit : l'heure n'a aucun sens sur une opération,
// et une heure parasite fausse toutes les comparaisons de dates.
DateTime aMinuit(DateTime d) => DateTime(d.year, d.month, d.day);

// Fin de la journée, pour borner la projection sans exclure le jour même.
DateTime aFinDeJournee(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59);

class Transaction {
  String libelle;
  int centimes;
  DateTime date;
  bool cochee;

  Transaction(this.libelle, this.centimes, DateTime date, {this.cochee = false})
      : date = aMinuit(date);

  Map<String, dynamic> versMap() => {
        'libelle': libelle,
        'centimes': centimes,
        'date': date.toIso8601String(),
        'cochee': cochee,
      };

  factory Transaction.depuisMap(Map<String, dynamic> map) {
    // Les enregistrements d'avant le passage aux centimes portent un
    // champ 'montant' en euros : on les convertit à la volée.
    final int centimes;
    if (map.containsKey('centimes')) {
      centimes = map['centimes'] as int;
    } else {
      centimes = ((map['montant'] as num).toDouble() * 100).round();
    }

    return Transaction(
      map['libelle'] as String,
      centimes,
      DateTime.parse(map['date'] as String),
      cochee: map['cochee'] as bool,
    );
  }
}

class MoneyK1000App extends StatelessWidget {
  const MoneyK1000App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyK1000',
      home: const EcranAccueil(),
    );
  }
}

class EcranAccueil extends StatefulWidget {
  const EcranAccueil({super.key});

  @override
  State<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends State<EcranAccueil> {
  int _soldeReferenceCentimes = 3000;
  final List<Transaction> _transactions = [];

  DateTime _dateProjection = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  );

  @override
  void initState() {
    super.initState();
    _charger();
  }

  // ---------------------------------------------------------------
  // Enregistrement sur le téléphone
  // ---------------------------------------------------------------

  Future<void> _charger() async {
    final prefs = await SharedPreferences.getInstance();

    final soldeCentimes = prefs.getInt('soldeReferenceCentimes');
    final ancienSolde = prefs.getDouble('soldeInitial'); // ancien format
    final listeEnregistree = prefs.getStringList('transactions');
    final dateEnregistree = prefs.getString('dateProjection');

    setState(() {
      if (soldeCentimes != null) {
        _soldeReferenceCentimes = soldeCentimes;
      } else if (ancienSolde != null) {
        _soldeReferenceCentimes = (ancienSolde * 100).round();
      }

      if (listeEnregistree != null) {
        _transactions.clear();
        for (final ligne in listeEnregistree) {
          _transactions.add(
            Transaction.depuisMap(jsonDecode(ligne) as Map<String, dynamic>),
          );
        }
        _trier();
      }

      if (dateEnregistree != null) {
        _dateProjection = aMinuit(DateTime.parse(dateEnregistree));
      }
    });

    // Réenregistre aussitôt au nouveau format (centimes, dates à minuit).
    _sauvegarder();
  }

  Future<void> _sauvegarder() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('soldeReferenceCentimes', _soldeReferenceCentimes);
    await prefs.remove('soldeInitial');
    await prefs.setStringList(
      'transactions',
      _transactions.map((t) => jsonEncode(t.versMap())).toList(),
    );
    await prefs.setString('dateProjection', _dateProjection.toIso8601String());
  }

  // ---------------------------------------------------------------
  // Calculs
  // ---------------------------------------------------------------

  // Le solde affiché : la référence, plus les seules opérations cochées.
  int get _soldeCentimes {
    var total = _soldeReferenceCentimes;
    for (final t in _transactions) {
      if (t.cochee) {
        total += t.centimes;
      }
    }
    return total;
  }

  // Le solde prévisionnel : le solde actuel, plus tout ce qui n'est pas
  // encore coché et qui tombe avant la fin de la journée de projection.
  int get _soldeProjeteCentimes {
    final limite = aFinDeJournee(_dateProjection);
    var total = _soldeCentimes;
    for (final t in _transactions) {
      if (!t.cochee && !t.date.isAfter(limite)) {
        total += t.centimes;
      }
    }
    return total;
  }

  String _formaterDate(DateTime d) {
    final jour = d.day.toString().padLeft(2, '0');
    final mois = d.month.toString().padLeft(2, '0');
    return '$jour/$mois';
  }

  void _trier() {
    _transactions.sort((a, b) => a.date.compareTo(b.date));
  }

  DateTime _memeJourMoisSuivant(DateTime d) {
    final dernierJour = DateTime(d.year, d.month + 2, 0).day;
    final jour = d.day > dernierJour ? dernierJour : d.day;
    return DateTime(d.year, d.month + 1, jour);
  }

  // Lit un montant saisi au clavier et le convertit en centimes.
  // Renvoie null si la saisie n'est pas un nombre.
  int? _lireCentimes(String saisie) {
    final valeur = double.tryParse(saisie.replaceAll(',', '.').trim());
    if (valeur == null) return null;
    return (valeur * 100).round();
  }

  // ---------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------

  Future<void> _modifierSolde() async {
    final controleur = TextEditingController(
      text: formaterMontant(_soldeReferenceCentimes),
    );

    final nouveauSolde = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le solde de référence'),
        content: TextField(
          controller: controleur,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(suffixText: '€'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _lireCentimes(controleur.text)),
            child: const Text('Valider'),
          ),
        ],
      ),
    );

    // On attend la fin de l'animation de fermeture : le champ de saisie
    // utilise encore le contrôleur tant que la fenêtre est à l'écran.
    Future.delayed(const Duration(seconds: 1), controleur.dispose);

    if (nouveauSolde != null) {
      setState(() {
        _soldeReferenceCentimes = nouveauSolde;
      });
      _sauvegarder();
    }
  }

  Future<void> _modifierDateProjection() async {
    final maintenant = DateTime.now();
    final premierJourDuMois = DateTime(maintenant.year, maintenant.month, 1);
    final dernierJourDuMois =
        DateTime(maintenant.year, maintenant.month + 1, 0);

    final choisie = await showDatePicker(
      context: context,
      initialDate: _dateProjection,
      firstDate: premierJourDuMois,
      lastDate: dernierJourDuMois,
    );
    if (choisie != null) {
      setState(() {
        _dateProjection = aMinuit(choisie);
      });
      _sauvegarder();
    }
  }

  // Ouvre le formulaire. Si [initiale] est fournie, on est en modification.
  Future<Transaction?> _saisirTransaction({Transaction? initiale}) async {
    final libelleControleur =
        TextEditingController(text: initiale?.libelle ?? '');
    final montantControleur = TextEditingController(
      text: initiale == null ? '' : formaterMontant(initiale.centimes.abs()),
    );
    bool estDepense = initiale == null ? true : initiale.centimes < 0;
    DateTime date = initiale?.date ?? DateTime.now();
    String? erreur;

    final resultat = await showDialog<Transaction>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialogue) => AlertDialog(
          title: Text(
            initiale == null
                ? 'Nouvelle transaction'
                : 'Modifier la transaction',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToggleButtons(
                  isSelected: [estDepense, !estDepense],
                  onPressed: (index) {
                    setStateDialogue(() {
                      estDepense = index == 0;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  selectedColor: Colors.white,
                  fillColor: estDepense ? Colors.red : Colors.green,
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text('Dépense'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text('Recette'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: libelleControleur,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Libellé'),
                ),
                TextField(
                  controller: montantControleur,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Montant',
                    suffixText: '€',
                    errorText: erreur,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text('Date : ${_formaterDate(date)}')),
                    TextButton(
                      onPressed: () async {
                        final choisie = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (choisie != null) {
                          setStateDialogue(() {
                            date = choisie;
                          });
                        }
                      },
                      child: const Text('Changer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                final libelle = libelleControleur.text.trim();
                final centimes = _lireCentimes(montantControleur.text);

                if (libelle.isEmpty) {
                  setStateDialogue(() {
                    erreur = 'Indique d\'abord un libellé';
                  });
                  return;
                }
                if (centimes == null || centimes == 0) {
                  setStateDialogue(() {
                    erreur = 'Montant invalide';
                  });
                  return;
                }

                final signe = estDepense ? -centimes.abs() : centimes.abs();
                Navigator.pop(context, Transaction(libelle, signe, date));
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );

    Future.delayed(const Duration(seconds: 1), () {
      libelleControleur.dispose();
      montantControleur.dispose();
    });

    return resultat;
  }

  Future<void> _ajouterTransaction() async {
    final transaction = await _saisirTransaction();
    if (transaction != null) {
      setState(() {
        _transactions.add(transaction);
        _trier();
      });
      _sauvegarder();
    }
  }

  Future<void> _modifierTransaction(int index) async {
    final ancienne = _transactions[index];
    final modifiee = await _saisirTransaction(initiale: ancienne);
    if (modifiee != null) {
      setState(() {
        modifiee.cochee = ancienne.cochee;
        _transactions[index] = modifiee;
        _trier();
      });
      _sauvegarder();
    }
  }

  // Fenêtre commune aux deux croix rouges.
  Future<String?> _demanderSuppression(String resume) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(resume),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, 'comptabiliser'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: const Text('Comptabiliser et supprimer'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'supprimer'),
            child: const Text(
              'Supprimer',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _supprimerTransaction(int index) async {
    final t = _transactions[index];
    final choix = await _demanderSuppression(
      '${t.libelle} — ${formaterMontant(t.centimes)} €',
    );
    if (choix == null) return;

    setState(() {
      if (choix == 'comptabiliser') {
        _soldeReferenceCentimes += t.centimes;
      }
      _transactions.removeAt(index);
    });
    _sauvegarder();
  }

  Future<void> _supprimerCochees() async {
    final cochees = _transactions.where((t) => t.cochee).toList();
    if (cochees.isEmpty) return;

    var total = 0;
    for (final t in cochees) {
      total += t.centimes;
    }

    final choix = await _demanderSuppression(
      '${cochees.length} opération(s) cochée(s) — ${formaterMontant(total)} €',
    );
    if (choix == null) return;

    setState(() {
      if (choix == 'comptabiliser') {
        _soldeReferenceCentimes += total;
      }
      _transactions.removeWhere((t) => t.cochee);
    });
    _sauvegarder();
  }

  // Reporte la transaction : son montant est encaissé sur le solde, et la
  // ligne est repoussée au même jour du mois suivant.
  void _reporterTransaction(int index) {
    final t = _transactions[index];
    setState(() {
      _soldeReferenceCentimes += t.centimes;
      t.date = aMinuit(_memeJourMoisSuivant(t.date));
      t.cochee = false;
      _trier();
    });
    _sauvegarder();
  }

  void _reporterCochees() {
    setState(() {
      for (final t in _transactions) {
        if (t.cochee) {
          _soldeReferenceCentimes += t.centimes;
          t.date = aMinuit(_memeJourMoisSuivant(t.date));
          t.cochee = false;
        }
      }
      _trier();
    });
    _sauvegarder();
  }

  // ---------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final solde = _soldeCentimes;
    final projete = _soldeProjeteCentimes;
    final aDesCochees = _transactions.any((t) => t.cochee);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MoneyK1000'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Solde : ${formaterMontant(_soldeReferenceCentimes)} €',
                    style: TextStyle(
                      fontSize: 32,
                      color: _soldeReferenceCentimes < 0
                          ? Colors.orange
                          : Colors.black,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _modifierSolde,
              ),
              if (aDesCochees) ...[
                IconButton(
                  icon: const Icon(Icons.published_with_changes),
                  onPressed: _reporterCochees,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: _supprimerCochees,
                ),
              ],
            ],
          ),
          if (aDesCochees) ...[
            const SizedBox(height: 8),
            Text(
              'Après opérations cochées : ${formaterMontant(solde)} €',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: solde < 0 ? Colors.orange : Colors.black87,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FloatingActionButton(
            onPressed: _ajouterTransaction,
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _transactions.length,
              itemBuilder: (context, index) {
                final t = _transactions[index];

                final changementDeMois = index > 0 &&
                    (t.date.month != _transactions[index - 1].date.month ||
                        t.date.year != _transactions[index - 1].date.year);

                return Column(
                  children: [
                    if (changementDeMois)
                      const Divider(thickness: 2, height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            _formaterDate(t.date),
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(t.libelle)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _modifierTransaction(index),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.published_with_changes,
                              size: 20,
                            ),
                            onPressed: () => _reporterTransaction(index),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.close,
                              size: 20,
                              color: Colors.red,
                            ),
                            onPressed: () => _supprimerTransaction(index),
                          ),
                          Text(
                            '${formaterMontant(t.centimes)} €',
                            style: TextStyle(
                              color:
                                  t.centimes < 0 ? Colors.red : Colors.green,
                            ),
                          ),
                          Checkbox(
                            visualDensity: VisualDensity.compact,
                            value: t.cochee,
                            onChanged: (valeur) {
                              setState(() {
                                t.cochee = valeur ?? false;
                              });
                              _sauvegarder();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.grey.shade200,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Solde au ${_formaterDate(_dateProjection)} : '
                    '${formaterMontant(projete)} €',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: projete < 0 ? Colors.red : Colors.black,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: _modifierDateProjection,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
