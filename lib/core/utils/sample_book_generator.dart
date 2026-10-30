import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../features/processing/services/pdf_processing_pipeline.dart';
import '../database/app_database.dart';

class SampleBookGenerator {
  static Future<Book> generateAndImportSampleBook(
      PdfProcessingPipeline pipeline) async {
    final tempDir = await getTemporaryDirectory();
    final samplePdfFile = File(p.join(tempDir.path, 'sherlock_holmes_sample.pdf'));

    final document = PdfDocument();
    document.documentInformation.title = 'The Adventures of Sherlock Holmes';
    document.documentInformation.author = 'Arthur Conan Doyle';
    document.documentInformation.subject = 'Classic Detective Mystery';

    final fontHeader = PdfStandardFont(PdfFontFamily.helvetica, 18, style: PdfFontStyle.bold);
    final fontBody = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final brush = PdfSolidBrush(PdfColor(20, 20, 20));

    // Chapter 1 Page
    final page1 = document.pages.add();
    page1.graphics.drawString(
      'CHAPTER I. A SCANDAL IN BOHEMIA',
      fontHeader,
      bounds: const Rect.fromLTWH(0, 0, 480, 30),
      brush: brush,
    );
    page1.graphics.drawString(
      'To Sherlock Holmes she is always THE woman. I have seldom heard him mention her under any other name. In his eyes she eclipses and predominates the whole of her sex. It was not that he felt any emotion akin to love for Irene Adler. All emotions, and that one particularly, were abhorrent to his cold, precise but admirably balanced mind.\n\nHe was, I take it, the most perfect reasoning and observing machine that the world has seen, but as a lover he would have placed himself in a false position. He never spoke of the softer passions, save with a gibe and a sneer. They were admirable things for the observer—excellent for drawing the veil from men’s motives and actions. But for the trained reasoner to admit such intrusions into his own delicate and finely adjusted temperament was to introduce a distracting factor which might throw a doubt upon all his mental results.\n\nGrit in a sensitive instrument, or a crack in one of his own high-power lenses, would not be more disturbing than a strong emotion in a nature such as his. And yet there was but one woman to him, and that woman was the late Irene Adler, of dubious and questionable memory.',
      fontBody,
      bounds: const Rect.fromLTWH(0, 40, 480, 600),
      brush: brush,
    );

    // Chapter 2 Page
    final page2 = document.pages.add();
    page2.graphics.drawString(
      'CHAPTER II. THE RED-HEADED LEAGUE',
      fontHeader,
      bounds: const Rect.fromLTWH(0, 0, 480, 30),
      brush: brush,
    );
    page2.graphics.drawString(
      'I had called upon my friend, Mr. Sherlock Holmes, one day in the autumn of last year and found him in deep conversation with a very stout, florid-faced, elderly gentleman with fiery red hair. With an apology for my intrusion, I was about to withdraw when Holmes pulled me abruptly into the room and closed the door behind me.\n\n“You could not have come at a better time, my dear Watson,” he said cordially.\n\n“I was afraid that you were engaged.”\n\n“So I am. Very much so.”\n\n“Then I can wait in the next room.”\n\n“Not at all. This gentleman, Mr. Wilson, has been my partner and helper in many of my most successful cases, and I have no doubt that he will be of the utmost use to me in yours also.”\n\nThe stout gentleman rose from his chair and gave a bob of greeting, with a quick little questioning glance from his small fat-encircled eyes.',
      fontBody,
      bounds: const Rect.fromLTWH(0, 40, 480, 600),
      brush: brush,
    );

    // Chapter 3 Page
    final page3 = document.pages.add();
    page3.graphics.drawString(
      'CHAPTER III. A CASE OF IDENTITY',
      fontHeader,
      bounds: const Rect.fromLTWH(0, 0, 480, 30),
      brush: brush,
    );
    page3.graphics.drawString(
      '“My dear fellow,” said Sherlock Holmes as we sat on either side of the fire in his lodgings at Baker Street, “life is infinitely stranger than anything which the mind of man could invent. We would not dare to conceive the things which are really mere commonplaces of existence. If we could fly out of that window hand in hand, hover over this great city, gently remove the roofs, and peep in at the queer things which are going on, the strange coincidences, the plannings, the cross-purposes, the wonderful chains of events, working through generations, and leading to the most outre results, it would make all fiction with its conventionalities and foreseen conclusions most stale and unprofitable.”\n\n“And yet I am not convinced of it,” I answered. “The cases which come to light in the papers are, as a rule, bald enough, and vulgar enough. There is realism, but there are no surprising deductions.”',
      fontBody,
      bounds: const Rect.fromLTWH(0, 40, 480, 600),
      brush: brush,
    );

    final pdfBytes = document.saveSync();
    document.dispose();

    await samplePdfFile.writeAsBytes(pdfBytes);

    return pipeline.processAndImportPdf(
      pdfFile: samplePdfFile,
      customTitle: 'The Adventures of Sherlock Holmes',
      customAuthor: 'Arthur Conan Doyle',
    );
  }
}

