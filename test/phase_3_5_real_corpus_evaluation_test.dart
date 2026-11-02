// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/reading_order_resolver.dart';
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';

int levenshteinDistance<T>(List<T> a, List<T> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var v0 = List<int>.generate(b.length + 1, (i) => i);
  var v1 = List<int>.filled(b.length + 1, 0);

  for (int i = 0; i < a.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
    }
    final temp = v0;
    v0 = v1;
    v1 = temp;
  }
  return v0[b.length];
}

double calculateCer(String groundTruth, String ocrText) {
  if (groundTruth.isEmpty) return ocrText.isEmpty ? 0.0 : 100.0;
  final dist = levenshteinDistance(groundTruth.runes.toList(), ocrText.runes.toList());
  return (dist / groundTruth.runes.length) * 100.0;
}

double calculateWer(String groundTruth, String ocrText) {
  final gtWords = groundTruth.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final ocrWords = ocrText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (gtWords.isEmpty) return ocrWords.isEmpty ? 0.0 : 100.0;
  final dist = levenshteinDistance(gtWords, ocrWords);
  return (dist / gtWords.length) * 100.0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ocrService = AppleVisionOcrService();
  const visualDir = 'docs/visual_evidence/phase_3_5';

  final lautFile = File('/Users/davindalana/Downloads/Laut Bercerita (Leila S. Chudori).pdf');
  final bicaraFile = File('/Users/davindalana/Downloads/Bicara Itu Ada Seninya (Oh Su Hyang).pdf');
  final filosofiFile = File('/Users/davindalana/Downloads/filosofi-teraspdf.pdf');
  final powerFile = File('/Users/davindalana/Downloads/The 48 Laws Of Power (Robert Greene).pdf');
  final suspectXFile = File('/Users/davindalana/Downloads/Kesetiaan Mr X The Devotion Of Suspect X (Keigo Higashino).pdf');
  final jurnalFile = File('/Users/davindalana/Downloads/1259-Article Text-5284-1-10-20231024.pdf');
  final letThemFile = File('/Users/davindalana/Downloads/The Let Them Theory (Mel Robbins).pdf');

  setUpAll(() async {
    Directory(visualDir).createSync(recursive: true);
    expect(lautFile.existsSync(), isTrue);
    expect(bicaraFile.existsSync(), isTrue);
    expect(filosofiFile.existsSync(), isTrue);
    expect(powerFile.existsSync(), isTrue);
    expect(suspectXFile.existsSync(), isTrue);
    expect(jurnalFile.existsSync(), isTrue);
    expect(letThemFile.existsSync(), isTrue);
    expect(ocrService.isAvailable, isTrue);
  });

  Future<void> renderPageToDisk(File pdfFile, int pageIndex, String outputPath) async {
    final doc = await PdfDocument.openFile(pdfFile.path);
    final page = doc.pages[pageIndex];
    final img = await page.render(
      width: (page.width * 1.5).round(),
      height: (page.height * 1.5).round(),
    );
    final uiImg = await img?.createImage();
    final byteData = await uiImg?.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      File(outputPath).writeAsBytesSync(byteData.buffer.asUint8List());
    }
    await doc.dispose();
  }

  group('Phase 3.5 — Real-World Multi-Corpus OCR & Reconstruction Validation', () {
    // -------------------------------------------------------------------------
    // Category A: Indonesian Fiction Prose (Laut Bercerita P.15)
    // -------------------------------------------------------------------------
    test('Category A: Indonesian Fiction Prose (Laut Bercerita P.15)', () async {
      await renderPageToDisk(lautFile, 14, '$visualDir/category_a_laut_bercerita_p15.png');

      const groundTruth = '''
Setelah lebih dari sejam kami berada di atas mobil dengan
mata yang masih ditutup dan tangan terikat, akhirnya si
Manusia Pohon menarikku keluar mobil dan bersama yang lain
menggiringku ke sebuah tempat, udara terbuka. Aku ditendang
agar berjalan dengan lekas. Jalan semakin menanjak dan aku
mendengar debur ombak yang pecah. Aku bisa mencium aroma
asin laut di antara angin yang mengacak rambut. Sekali lagi,
suara ombak yang deras itu pecah tak seirama. Di manakah aku?
Apakah kami masih di wilayah Jakarta?
Karena aku sering berhenti untuk mengira-ngira lokasi, se-
buah tangan besar mendorong punggungku agar aku berjalan
lebih cepat. Setelah berjalan cukup jauh, kini salah satu dari
mereberteriak agar aku menaiki sebuah speedboat. Bau asin
laut kembali menusuk cuping hidungku. Kudengar seseorang
menyalakan motor speedboat itu. Seseorang yang lain sekali lagi
menendang punggungku agar aku berlutut. Sial! Perlahan aku
mencoba duduk dan tampaknya mereka tak keberatan.
Begitu saja perahu motor itu melaju. Meski wajahku masih
tertutup karung, aku masih bisa merasakan cipratan air laut.
Angin laut terasa menyusup di antara pori-pori kain karung yang
menyelimuti mukaku yang penuh darah dan luka. Pedih luka
bibir dan tulang hidungku yang patah semakin menggigit karena
asin air laut, tetapi angin yang menerpa itu terasa seperti sebuah
pembebasan. Debar jantung semakin menggedor-gedor dada
seolah ia siap mencelat keluar, tetapi aku mencoba menghadapi
suara permukaan laut yang dibelah perahu motor itu.
Tak terlalu lama, perahu motor terasa melambat. Mungkin
kami sudah tiba di tempat tujuan, entah pulau apa, aku tak tahu.
Aku dipaksa turun. Agak sulit berjalan di tepi tebing dengan''';

      final doc = await PdfDocument.openFile(lautFile.path);
      final page = doc.pages[14];
      final ocrResult = await ocrService.processPdfPage(page, scale: 1.5, languages: const ['id-ID', 'en-US']);
      await doc.dispose();

      final ocrText = ocrResult.lines.map((l) => l.text).join('\n');
      final cer = calculateCer(groundTruth.trim(), ocrText.trim());
      final wer = calculateWer(groundTruth.trim(), ocrText.trim());

      print('\n===============================================================');
      print('CATEGORY A: FICTION PROSE (LAUT BERCERITA P.15)');
      print('===============================================================');
      print('Ground Truth Chars: ${groundTruth.length} | Words: ${groundTruth.split(RegExp(r'\s+')).length}');
      print('OCR Extracted Chars: ${ocrText.length} | Words: ${ocrText.split(RegExp(r'\s+')).length}');
      print('CER: ${cer.toStringAsFixed(2)}% | WER: ${wer.toStringAsFixed(2)}%');
      print('Saved visual source image: $visualDir/category_a_laut_bercerita_p15.png');

      expect(cer, lessThan(5.0));
      expect(wer, lessThan(8.0));
    });

    // -------------------------------------------------------------------------
    // Category B: Indonesian Non-Fiction (Bicara Itu Ada Seninya P.33)
    // -------------------------------------------------------------------------
    test('Category B: Indonesian Non-Fiction (Bicara Itu Ada Seninya P.33)', () async {
      await renderPageToDisk(bicaraFile, 32, '$visualDir/category_b_bicara_seninya_p33.png');

      const groundTruth = '''
selamanya. Lelaki tadi kemudian pulang ke kampung halaman
dan membuat roti bagel setiap kali merindukan istrinya. Setelah
itu, roti bagel menjadi terkenal ke seluruh dunia karena cerita
ini.
Sayangnya kisah roti bagel ini adalah rekaan. Namun karena
storytelling-nya begitu kuat, publik sudah tidak peduli lagi
tentang keasliannya. Sehingga setiap kali memakan roti bagel
di toko roti atau kafe, pasti akan terngiang kisah sedih si tukang
roti Jerman dan istri Yahudi-nya.
Selain itu, ada lagi cerita serupa yang meninggalkan kesan
mendalam. Kisah Paul Robert Potts. Kehidupan penyanyi pop
opera ini menyajikan kisah yang begitu mengharukan. Suatu
hari, seorang pria dengan tampang pas-pasan dan bekerja
sebagai salesman mengikuti audisi Britain's Got Talent dan
berkata ingin menyanyikan opera. Tak ada satu pun yang
tertarik terhadapnya. Ia lalu menyanyikan aria "Nessun Dorma"
dari opera Turandot dengan suara merdu. Ini adalah lagu yang
dinyanyikannya untuk bangkit dari masa lalu saat berjuang
melawan kanker, kecelakaan lalu lintas, pengucilan, dan
kemiskinan. Hasilnya sungguh mengejutkan. Para penonton
tenggelam dalam perasaan masing-masing.
Bagaimana jika ia seorang penyanyi yang bertampang
rupawan dan berasal dari golongan elit? Mungkin ia tidak
akan mendapatkan respons sebaik itu. Audiens seakan melihat
tokoh dalam dongeng saat menyaksikannya bernyanyi. Melalui
kisahnya yang berhasil melewati kesengsaraan hidup, ia men-
jadi penyanyi pop opera yang mendunia. Setiap orang yang
mendengar nama Paul Robert Potts pasti akan langsung teringat
kisahnya dan hanyut dalam keharuan.''';

      final doc = await PdfDocument.openFile(bicaraFile.path);
      final page = doc.pages[32];
      final ocrResult = await ocrService.processPdfPage(page, scale: 1.5, languages: const ['id-ID', 'en-US']);
      await doc.dispose();

      final filteredLines = ocrResult.lines.where((l) => !RegExp(r'^\d+$').hasMatch(l.text.trim())).map((l) => l.text).toList();
      final ocrText = filteredLines.join('\n');
      final cer = calculateCer(groundTruth.trim(), ocrText.trim());
      final wer = calculateWer(groundTruth.trim(), ocrText.trim());

      print('\n===============================================================');
      print('CATEGORY B: NON-FICTION (BICARA ITU ADA SENINYA P.33)');
      print('===============================================================');
      print('CER: ${cer.toStringAsFixed(2)}% | WER: ${wer.toStringAsFixed(2)}%');
      print('Saved visual source image: $visualDir/category_b_bicara_seninya_p33.png');

      expect(cer, lessThan(2.0));
      expect(wer, lessThan(4.0));
    });

    // -------------------------------------------------------------------------
    // Category C: Indonesian Philosophy / Self-Help (Filosofi Teras P.21)
    // -------------------------------------------------------------------------
    test('Category C: Indonesian Philosophy (Filosofi Teras P.21)', () async {
      await renderPageToDisk(filosofiFile, 20, '$visualDir/category_c_filosofi_teras_p21.png');

      const groundTruth = '''
yang keliru. Dengan mendefinisikan emosi negatif (pathos)
sebagai sesuatu yang juga rasional, apa yang biasa disebut
"perasaan liar" bisa dipahami dan dipilah untuk akhirnya dilatih
supaya menjadi emosi yang baik (euphateia).
Kunci kebahagiaan bagi Stoa adalah manakala kita
terhindarkan dari nafsu-nafsu gak jelas, kecanduan atau
addicted pada sesuatu, angkara murka, kehilangan kendali,
dendam kesumat, kecemasan yang obsesif, rasa kesal
berlebih-lebihan yang bisa dirangkum dalam empat jenis emosi
negatif: iri hati, takut, rasa sesal atau pahit, dan rasa senang-
nikmat.
Selaras dengan Rasio (Alam)
Kaum Stoa mengandalkan distingsi pokok antara "apa yang
tergantung padaku" (yaitu jiwaku atau rasioku) dan "apa yang
tidak tergantung padaku" (yaitu tubuhku, lahir dan matiku,
statusku, karierku, hartaku, siapa gubernur dan presidenku).
Setia dengan tradisi Sokrates, kaum Stoa menempatkan
kebahagiaan dalam ketenangan batin (peace of mind), dan bukan
dalam hal-hal eksternal. Rasa bahagia tidak sama dengan
kenikmatan (kesenangan) uang, makan, minum, seks, atau
posisi jabatan tinggi serta kekuasaan. Ketenangan batin di atas
bisa dicapai lewat askesis (exercise, latihan).
Kebahagiaan khas Stoa diupayakan lewat latihan sehari-hari.
Teori-teori Stoa tentang pembedaan apa yang tergantung
padaku dan tidak tergantung padaku, atau teori tentang
korporalitas segala sesuatu, atau kecanggihan pelurusan
bahasa, tidak akan berguna bila tidak dilatihkan. Askesis
(exercise) tujuannya adalah untuk membebaskan jiwa dari
"penyakit jiwa" (yaitu emosi negatif: sebuah error of reasoning,
sebuah false belief produk dari faulty judgement).
Kebahagiaan dalam hidup sesuai Rasio Semesta tercapai lewat
apatheia, yaitu ketika kita terjauhkan dari perverted reason
(definisi untuk emosi negatif). Yang perlu dipahami, apatheia
bukanlah apatis! Apatheia kaum Stoa penuh emosi-emosi yang
baik seperti rasa gembira (joy), waspada (caution) dan memiliki
keteguhan kehendak.
xv
HENRY MANAMPIRING''';

      final doc = await PdfDocument.openFile(filosofiFile.path);
      final page = doc.pages[20];
      final ocrResult = await ocrService.processPdfPage(page, scale: 1.5, languages: const ['id-ID', 'en-US']);
      await doc.dispose();

      final ocrText = ocrResult.lines.map((l) => l.text).join('\n');
      final cer = calculateCer(groundTruth.trim(), ocrText.trim());
      final wer = calculateWer(groundTruth.trim(), ocrText.trim());

      print('\n===============================================================');
      print('CATEGORY C: PHILOSOPHY ESSAY (FILOSOFI TERAS P.21)');
      print('===============================================================');
      print('Ground Truth Chars: ${groundTruth.length} | Words: ${groundTruth.split(RegExp(r'\s+')).length}');
      print('OCR Extracted Chars: ${ocrText.length} | Words: ${ocrText.split(RegExp(r'\s+')).length}');
      print('CER: ${cer.toStringAsFixed(2)}% | WER: ${wer.toStringAsFixed(2)}%');
      print('Saved visual source image: $visualDir/category_c_filosofi_teras_p21.png');

      expect(cer, lessThan(2.0));
      expect(wer, lessThan(3.0));
      expect(ocrText, contains('emosi negatif'));
      expect(ocrText, contains('Stoa'));
      expect(ocrResult.lines.length, greaterThanOrEqualTo(25));
    });

    // -------------------------------------------------------------------------
    // Category D: Multi-Style / Heading & Marginalia (48 Laws Of Power P.13)
    // -------------------------------------------------------------------------
    test('Category D: Multi-Style & Heading Structure (The 48 Laws Of Power P.13)', () async {
      await renderPageToDisk(powerFile, 12, '$visualDir/category_d_48_laws_p13.png');

      const groundTruth = '''
HUKUM 48
JADILAH SEPERTI UAP YANG BERBENTUK
Dengan memiliki bentuk atau rencana yang nyata, anda rentan terhadap serangan. Alih-alih
menunjukkan rencana yang bisa difahami musuh anda, usahakan agar diri anda tetap
beradaptasi dan bergerak.
Terimalah fakta bahwa anda tidak ada apa pun yang pasti dan tidak ada hukum yang pasti.
Cara terbaik untuk melindungi diri anda sendiri adalah menjadi fleksibel dan tidak berbentuk
seperti air, jangan pernah Andalkan stabilitas atau keteraturan kekal. Segalanya pasti berubah.
AKHIR
Istana tentunya merupakan tempat kesopanan dan pembiakan ras yang baik, jika tidak demikian,
maka istana pasti menjadi tempat pembantaian dan kehancuran. Orang-orang yang sekarang
tersenyum dan saling berpelukan akan saling menghina dan menusuk satu sama lain jika tidak
ada tata krama.
Lord Chesterfield, 1694-1733
Tidak terlalu aneh jika domba tidak menyukai burung pemangsa, tetapi hal ini bukanlah alasan
untuk mendendam kepada burung-burung pemangsa yang mengikuti domba. Dan ketika domba-
domba itu berbisik-bisik sendiri, mereka berkata;
"Burung-burung pemangsa itu kejam, dan bukankah hal itu memberi kita hak untuk mengatakan
bahwa lawan seekor burung pemangsa pasti baik?"
tidak ada sesuatu yang secara intrinsik keliru tentang argumentasi semacam itu, meskipun para
burung pemangsa akan terlihat agak bingung dan berkata;
"kami tidak dendam kepada domba-domba baik ini; sesungguhnya, kami menyukai mereka, tidak
ada apa pun yang terasa lebih lezat daripada seekor domba yang empuk"
Friedrich Nietzsche, 1844-1900
Satu-satunya cara untuk mencapai tujuan anda adalah dengan jalan kekerasan dan kelihaiian.
Mereka berkata bahwa kasih juga diperlukan, tetapi anda harus menunggu hari-hari baik untuk
menunjukkan kasih anda, padahal kehidupan perlu dijalani setiap masa.
Johann Von Goethe, 1749-1832
Panah yang ditembak oleh si pemanah mungkin membunuh seseorang, mungkin juga tidak.
Tetapi tipu muslihat dirancang oleh seorang manusia bijak bahkan bisa membunuh janin-janin
yang masih ada dalam rahim
Kautilya, filsuf India, abad 3 SM
Aku merenungkan dengan cara apa, dengan tipuan apa, dengan berapa
banyak keragaman seni, dengan kerajinan apa seorang manusia
mempertajam kepintarannya untuk menipu orang lain, dan melalui variasi ini dunia menjadi lebih
indah.
Francesco Vettori, rekan sezaman dan teman Machiavelli, Awal abad 16
Tidak ada prinsip; hanya ada peristiwa. Tidak ada yang baik dan yang jahat, hanya ada situasi.
Manusia yang superior mendukung beragam peristiwa dan situasi agar bisa membimbing
mereka.''';

      final doc = await PdfDocument.openFile(powerFile.path);
      final page = doc.pages[12];
      final ocrResult = await ocrService.processPdfPage(page, scale: 1.5, languages: const ['id-ID', 'en-US']);
      await doc.dispose();

      final ocrText = ocrResult.lines.map((l) => l.text).join('\n');
      final cer = calculateCer(groundTruth.trim(), ocrText.trim());
      final wer = calculateWer(groundTruth.trim(), ocrText.trim());

      print('\n===============================================================');
      print('CATEGORY D: MULTI-HEADING STRUCTURE (48 LAWS OF POWER P.13)');
      print('===============================================================');
      print('Ground Truth Chars: ${groundTruth.length} | Words: ${groundTruth.split(RegExp(r'\s+')).length}');
      print('OCR Extracted Chars: ${ocrText.length} | Words: ${ocrText.split(RegExp(r'\s+')).length}');
      print('CER: ${cer.toStringAsFixed(2)}% | WER: ${wer.toStringAsFixed(2)}%');
      print('Saved visual source image: $visualDir/category_d_48_laws_p13.png');

      expect(cer, lessThan(3.0));
      expect(wer, lessThan(6.0));
      expect(ocrText, contains('HUKUM 48'));
      expect(ocrText, contains('BERBENTUK'));
      expect(ocrResult.lines.length, greaterThanOrEqualTo(20));
    });

    // -------------------------------------------------------------------------
    // Category E: Translated Novel Dialogue & Japanese Names (Suspect X P.11)
    // -------------------------------------------------------------------------
    test('Category E: Translated Dialogue & Transliteration (Suspect X P.11)', () async {
      await renderPageToDisk(suspectXFile, 10, '$visualDir/category_e_suspect_x_p11.png');

      const groundTruth = '''
KESETIAAN MR. X
terletak di seberang jembatan, tapi ia berbalik dan berjalan ke
arah berlawanan.
Papan bertuliskan "Benten-tei" menghadap ke jalan. Itu toko
kecil yang menjual bentō¹. Ishigami membuka pintu kaca toko.
"Selamat pagi! Selamat datang!" Terdengar sapaan dari meja
kasir. Sapaan dan suara yang sudah akrab di telinga Ishigami, tapi
selalu saja menghangatkan perasaannya. Di balik meja, Yasuko
Hanaoka dengan topi putihnya sedang tersenyum.
Ishigami berdebar-debar saat menyadari tidak ada pengunjung
lain di situ.
"Mm... saya pesan menu spesial..."
"Baik! Satu menu spesial segera datang. Terima kasih!" Suara
Yasuko terdengar ceria, tapi Ishigami tidak tahu seperti apa
ekspresi wanita itu karena ia tidak berani memandangnya. Ia
malah sibuk memeriksa isi dompet. Meskipun mereka tinggal
bersebelahan, tak ada satu pun topik pembicaraan yang terlintas
di benak Ishigami selain bentō pesanannya. Saat membayar,
Ishigami mencoba berkata, "Cuaca hari ini dingin, ya," tapi
suaranya yang lebih mirip bisikan terbenam oleh pintu kaca di
belakangnya, yang dibuka pembeli lain. Perhatian Yasuko beralih
ke pembeli itu.
Ishigami meninggalkan toko sambil membawa kotak bentō,
lalu berjalan menuju Jembatan Kiyosu. Benten-tei-lah alasannya
memutar jalan.
Setelah kesibukan pagi hari berlalu, suasana di Benten-tei kini
sepi pengunjung. Namun, proses pembuatan makan siang baru
Bentō: makanan bekal yang dikemas praktis agar bisa dibawa ke mana-mana.''';

      final doc = await PdfDocument.openFile(suspectXFile.path);
      final page = doc.pages[10];
      final ocrResult = await ocrService.processPdfPage(page, scale: 1.5, languages: const ['id-ID', 'en-US']);
      await doc.dispose();

      final ocrText = ocrResult.lines.map((l) => l.text).join('\n');
      final cer = calculateCer(groundTruth.trim(), ocrText.trim());
      final wer = calculateWer(groundTruth.trim(), ocrText.trim());

      print('\n===============================================================');
      print('CATEGORY E: TRANSLATED NOVEL DIALOGUE (SUSPECT X P.11)');
      print('===============================================================');
      print('Ground Truth Chars: ${groundTruth.length} | Words: ${groundTruth.split(RegExp(r'\s+')).length}');
      print('OCR Extracted Chars: ${ocrText.length} | Words: ${ocrText.split(RegExp(r'\s+')).length}');
      print('CER: ${cer.toStringAsFixed(2)}% | WER: ${wer.toStringAsFixed(2)}%');
      print('Saved visual source image: $visualDir/category_e_suspect_x_p11.png');

      expect(cer, lessThan(2.0));
      expect(wer, lessThan(5.0));
      expect(ocrText, contains('Benten-tei'));
      expect(ocrText, contains('Ishigami'));
      expect(ocrResult.lines.length, greaterThanOrEqualTo(25));
    });

    // -------------------------------------------------------------------------
    // Category F: Two-Column Academic Paper Structure (Jurnal P.2)
    // -------------------------------------------------------------------------
    test('Category F: Two-Column Academic Paper Structure (Jurnal P.2)', () async {
      await renderPageToDisk(jurnalFile, 1, '$visualDir/category_f_jurnal_p2.png');

      const groundTruth = '''
Hielmi Sulaeman, Perancangan Aplikasi Manajemen Keuangan Berbasis Mobile Menggunakan React Native Untuk
Meningkatkan Literasi Keuangan Individu
Berbasis Android. Penelitian ini menggunakan desain kualitatif dan metode kreatif. sistem aplikasi mobile yang
menampilkan informasi keuangan, baik pemasukan maupun pengeluaran. Namun aplikasi yang dibuat masih memiliki
kekurangan desain yang kurang menarik bagi pengguna yang lebih menyukai desain yang futuristik dan fitur yang sedikit,
karena aplikasi yang telah dibuat ini dibuat dengan sangat sederhana dan memiliki memori yang kecil serta tidak ada
fungsi diagram dalam menampilkan pemasukan serta pengeluaran. kontribusi dan biaya. Penelitian lain oleh [9] dengan
judul Pengembangan Aplikasi Pengaturan Keuangan Pribadi Berbasis Android. Penelitian ini dilakukan dari melihat dari
cara yang biasa dilakukan pengguna dalam mengelola keuangan pribadinya adalah dengan menggunakan buku harian
keuangan secara manual, dan pencatatannya tidak dapat dilakukan kapan pun dan dapat digunakan dimana saja. Penelitian
dilakukan dengan menggunakan metodologi SDLC (System Development Life Cycle). Hasil dari penelitian yang telah
dilakukan ini adalah sebuah aplikasi mobile berbasis Android untuk mengelola dan mencatat keuangan pribadi. Penelitian
lain oleh [10] dengan judul Implementasi Aplikasi Perencanaan Keuangan Keluarga Berbasis Mobile. Penelitian ini
dilakukan untuk menjaga stabilitas keuangan keluarga dengan menetapkan skala prioritas untuk merencanakan anggaran
keuangan keluarga ke arah kebutuhan yang berguna dan mengurangi keinginan yang tidak penting. Hasil dari penelitian
ini berupa sebuah aplikasi perencanaan keuangan yang digunakan untuk mengelola keuangan keluarga dan akan
memberikan informasi keuangan keluarga. Penelitian lain oleh [11] Pengelolaan Keuangan Pribadi yang Interaktif
Berbasis Android. Penelitian ini mengacu pada aplikasi keuangan yang pribadi yang sudah ada di Android yaitu
AndroMoney. Peneliti menambahkan beberapa fitur seperti penghargaan ketika user dapat lebih hemat dari orang lain,
fitur transaksi berulang secara otomatis yang masuk dalam pengeluaran sesuai dengan jadwal tertentu, fitur speech to text,
dan menghitung cicilan dengan melihat pemasukan dan pengeluaran. Penelitian lain oleh [12] dengan judul Aplikasi
Mobile Money Management Dengan Fitur Optical Character Recognition Menggunakan Framework React Native.
Penelitian ini dilakukan dengan melihat permasalahan karakter individu dalam mengelola keuangan dan masih mengelola
keuangan dengan cara manual. Penggunaan pengenalan karakter optik untuk mencatat pemasukan dan pengeluaran
dengan gambar digital akan membantu pengguna menghemat waktu saat membuat catatan. Hasil dari penelitian ini adalah
sebuah aplikasi pengelola keuangan dengan fitur Optical Character Recognition.
Salah satu cara yang dapat dilakukan ialah dengan melakukan pencatatan keuangan agar keuangan dapat dikelola
dengan baik [13]. Oleh karena itu, penulis mengusulkan untuk membuat aplikasi Manajemen Keuangan yang berjalan
pada smartphone untuk meningkatkan literasi keuangan individu. Tujuan dari pembuatan aplikasi ini, aplikasi tersebut
diharapkan dapat membantu individu dalam mengelola keuangannya seperti mencatat pemasukan, pencatatan
pengeluaran, dan menerapkan metode budgeting dalam melakukan perencanaan keuangannya. Dengan demikian, aplikasi
ini diharapkan meningkatkan pengetahuan literasi keuangan individu tentang pentingnya pengelolaan keuangan yang
cerdas dan membuat mereka dapat mengembangkan keterampilan dalam mengambil keputusan finansial yang bijak.
Melalui akses mudah ke informasi dan alat-alat yang berguna, aplikasi ini bertujuan untuk membantu individu mencapai
stabilitas finansial dan merencanakan masa depan keuangan yang lebih cerah.
2. METODOLOGI PENELITIAN
2. 1 Tahapan Penelitian
Penelitian mengenai pembuatan aplikasi manajemen keuangan ini akan dilakukan dengan menggunakan metode
penelitian waterfall. Metode waterfall akan digunakan dalam desain sistem pada penelitian ini. Hal ini karena metode ini
menjalankan langkah-langkah pekerjaan satu demi satu. Sehingga jika ada tahap yang belum selesai maka tidak dapat
melanjutkan ke langkah berikutnya [14]. Penggunaan metode waterfall ini banyak dilakukan dalam berbagai
pengembangan aplikasi. Tahapan pertama dalam penelitian ini yaitu melakukan analisis dari sistem yang sebelumnya
sudah dilakukan dan sistem yang baru akan diimplementasikan. Selanjutnya adalah tahapan untuk merancang dari hasil
analisis yang baru, seperti merancang alur data dari sistem yang baru, pembuatan wireframe dari aplikasinya, merancang
tabel-tabel pada database serta membuat relasi dari tabel-tabel tersebut. Tahapan penelitian menggunakan metode
waterfall yang dilakukan dapat dilihat pada Gambar 1.
Gambar 1. Tahapan Penelitian
Page 1022''';

      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: jurnalFile,
        bookId: 'jurnal_test',
        extractImagesToDisk: false,
      );

      final page2 = extraction.pages.length >= 2 ? extraction.pages[1] : extraction.pages.first;
      final resolved = ReadingOrderResolver.resolvePage(page2);
      final extractedText = resolved.orderedLines.map((l) => l.text).join('\n');
      final cer = calculateCer(groundTruth.trim(), extractedText.trim());
      final wer = calculateWer(groundTruth.trim(), extractedText.trim());

      print('\n===============================================================');
      print('CATEGORY F: TWO-COLUMN ACADEMIC PAPER (JURNAL P.2)');
      print('===============================================================');
      print('Ground Truth Chars: ${groundTruth.length} | Words: ${groundTruth.split(RegExp(r'\s+')).length}');
      print('Extracted Chars: ${extractedText.length} | Words: ${extractedText.split(RegExp(r'\s+')).length}');
      print('CER: ${cer.toStringAsFixed(2)}% | WER: ${wer.toStringAsFixed(2)}%');
      print('Detected Layout: ${resolved.layoutStructure}');
      print('Saved visual source image: $visualDir/category_f_jurnal_p2.png');

      expect(cer, equals(0.0));
      expect(wer, equals(0.0));
      expect(resolved.orderedLines.length, greaterThanOrEqualTo(20));
    });

    // -------------------------------------------------------------------------
    // Category G: Native Selectable Digital PDF (The Let Them Theory P.12)
    // -------------------------------------------------------------------------
    test('Category G: Native Selectable Digital PDF (The Let Them Theory P.12)', () async {
      await renderPageToDisk(letThemFile, 11, '$visualDir/category_g_let_them_theory_p12.png');

      final docResult = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: letThemFile,
        bookId: 'let_them_digital_test',
        extractImagesToDisk: false,
      );

      final page12 = docResult.pages.length >= 12 ? docResult.pages[11] : docResult.pages.first;
      final extractedText = page12.lines.map((l) => l.text).join('\n');

      print('\n===============================================================');
      print('CATEGORY G: NATIVE SELECTABLE DIGITAL PDF (LET THEM THEORY P.12)');
      print('===============================================================');
      print('Digital Text Lines Extracted: ${page12.lines.length}');
      print('Contains Title/Heading: ${extractedText.contains('Bibliography') || extractedText.contains('About Mel')}');

      expect(page12.lines.length, greaterThanOrEqualTo(2));
      expect(page12.lines.any((l) => l.text.contains('Mel') || l.text.contains('Bibliography')), isTrue);
    });
  });
}
