// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';

void main() {
  group('Phase 3.5 — Text Normalization Integrity & Linguistic Safety', () {
    test(
      '1. Preposition vs Passive Prefix: Strict isolation of locational/spatial complements',
      () {
        // Negative tests: Prepositional phrases that must NEVER be merged into passive verbs
        final prepositionPhrases = [
          'di rumah',
          'di kantor',
          'di sekolah',
          'di mana',
          'di sini',
          'di sana',
          'di atas',
          'di bawah',
          'di dalam',
          'di luar',
          'di tengah',
          'di samping',
          'di depan',
          'di belakang',
          'di seberang',
          'di sekitar',
          'di tempat',
          'di hari',
          'di tahun',
          'di abad',
        ];

        for (final phrase in prepositionPhrases) {
          final cleaned = ParagraphReconstructor.cleanOcrText(phrase);
          expect(
            cleaned,
            equals(phrase),
            reason: 'Preposition "$phrase" must remain separated',
          );
        }

        // Positive tests: Passive verbs with 'di-' prefix that were split by OCR space
        final passiveVerbsSplit = {
          'di tutup': 'ditutup',
          'di buka': 'dibuka',
          'di baca': 'dibaca',
          'di tulis': 'ditulis',
          'di ambil': 'diambil',
          'di dorong': 'didorong',
          'di tendang': 'ditendang',
          'di temukan': 'ditemukan',
          'di lakukan': 'dilakukan',
          'di buat': 'dibuat',
          'di dengar': 'didengar',
          'di sebut': 'disebut',
          'di terima': 'diterima',
          'di kirim': 'dikirim',
          'di lihat': 'dilihat',
          'di rawat': 'dirawat',
          'di jaga': 'dijaga',
          'di lepas': 'dilepas',
          'di simpan': 'disimpan',
          'di letakkan': 'diletakkan',
        };

        passiveVerbsSplit.forEach((splitForm, expectedJoined) {
          final cleaned = ParagraphReconstructor.cleanOcrText(splitForm);
          expect(
            cleaned,
            equals(expectedJoined),
            reason:
                'Passive verb "$splitForm" must be merged into "$expectedJoined"',
          );
        });
      },
    );

    test(
      '2. Stray hyphen normalization does not corrupt compound words or prepositions',
      () {
        // Prepositions with stray hyphen: "di- rumah" -> "di rumah"
        expect(
          ParagraphReconstructor.cleanOcrText('di- rumah'),
          equals('di rumah'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('di- kantor'),
          equals('di kantor'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('di- mana'),
          equals('di mana'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('ke- pasar'),
          equals('ke pasar'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('ke- sekolah'),
          equals('ke sekolah'),
        );

        // Affix splits with stray hyphen: "di- tutup" -> "ditutup"
        expect(
          ParagraphReconstructor.cleanOcrText('di- tutup'),
          equals('ditutup'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('di- ambil'),
          equals('diambil'),
        );
        expect(ParagraphReconstructor.cleanOcrText('ke- dua'), equals('kedua'));
        expect(
          ParagraphReconstructor.cleanOcrText('ke- tiga'),
          equals('ketiga'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('pem- bangunan'),
          equals('pembangunan'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('ber- lari'),
          equals('berlari'),
        );

        // Reduplications with stray hyphen: "anak- anak" -> "anak-anak"
        expect(
          ParagraphReconstructor.cleanOcrText('anak- anak'),
          equals('anak-anak'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('tiba- tiba'),
          equals('tiba-tiba'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('berulang- ulang'),
          equals('berulang-ulang'),
        );

        // Distinct compound words with hyphen and space: "siang- malam" -> "siang-malam" (NEVER "siangmalam")
        expect(
          ParagraphReconstructor.cleanOcrText('siang- malam'),
          equals('siang-malam'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('ibu- bapak'),
          equals('ibu-bapak'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('tua- muda'),
          equals('tua-muda'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('sayur- mayur'),
          equals('sayur-mayur'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('lauk- pauk'),
          equals('lauk-pauk'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('ramah- tamah'),
          equals('ramah-tamah'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('suami- istri'),
          equals('suami-istri'),
        );

        // CRIT-01 Fix Verification: Standard word syllables split across lines must be joined without hyphen
        // (NEVER falsely converted to hyphenated compound words even if both parts length >= 3)
        expect(
          ParagraphReconstructor.cleanOcrText('dok- umen'),
          equals('dokumen'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('kom- puter'),
          equals('komputer'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('sta- bilitas'),
          equals('stabilitas'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('par- agraf'),
          equals('paragraf'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('res- pons'),
          equals('respons'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('trans- portasi'),
          equals('transportasi'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('struk- tur'),
          equals('struktur'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('in- formasi'),
          equals('informasi'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('ha- laman'),
          equals('halaman'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('ka- limat'),
          equals('kalimat'),
        );
        expect(
          ParagraphReconstructor.cleanOcrText('kon- teks'),
          equals('konteks'),
        );
      },
    );

    test('3. Idempotency Audit: cleanOcrText(cleanOcrText(x)) == cleanOcrText(x)', () {
      final corpusSamples = [
        'Setelah lebih dari sejam kami berada di atas mobil dengan mata yang masih ditutup.',
        'Ia berjalan ke seberang jembatan untuk menemui temannya di kantor pos.',
        'Anak-anak berlari-lari di lapangan terbuka siang-malam tanpa lelah.',
        'Pembangunan gedung itu telah direncanakan sejak sepuluh tahun yang lalu.',
        'Buku ini diterbitkan oleh Gramedia Pustaka Utama. ISBN 978-602-03-8591-4.',
        '“Apakah kamu sudah membaca bab kedua?” tanya Kinan sambil tersenyum.',
        'Di mana-mana orang membicarakan peristiwa yang terjadi di rumah tua itu.',
        'Surat tersebut telah dikirim dan diterima oleh pihak yang bersangkutan.',
      ];

      for (final sample in corpusSamples) {
        final pass1 = ParagraphReconstructor.cleanOcrText(sample);
        final pass2 = ParagraphReconstructor.cleanOcrText(pass1);
        final pass3 = ParagraphReconstructor.cleanOcrText(pass2);

        expect(
          pass2,
          equals(pass1),
          reason: 'Pass 2 must be identical to Pass 1 for: "$sample"',
        );
        expect(
          pass3,
          equals(pass1),
          reason: 'Pass 3 must be identical to Pass 1 for: "$sample"',
        );
      }
    });

    test(
      '4. Preservation of Author Intent: Informal or un-standardized words are not mutated',
      () {
        // If an author wrote "diluar" (informal/unstandardized), system should preserve it
        expect(
          ParagraphReconstructor.cleanOcrText('dia menunggu diluar ruangan'),
          equals('dia menunggu diluar ruangan'),
        );
        // If author wrote "dimana", preserve author source text
        expect(
          ParagraphReconstructor.cleanOcrText(
            'dimana ada kemauan disitu ada jalan',
          ),
          equals('dimana ada kemauan disitu ada jalan'),
        );
      },
    );
  });
}
