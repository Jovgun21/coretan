# Peta implementasi: spec → kode

Referensi silang terhadap spesifikasi 20 bagian, plus hal yang sengaja belum dikerjakan.

## Selesai (Tahap 1 + sebagian Tahap 2)

| Spec | Fitur | Berkas |
|---|---|---|
| 2.1 Pen tool | gaya, ketebalan, warna, preset, pressure, tilt | `Core/InkTypes.swift`, `Rendering/InkCanvasView.swift`, `UI/PenPalette.swift` |
| 2.2 Highlighter | warna, ketebalan, transparansi, ada di atas konten | `Rendering/StrokeRenderer.swift` (alpha 0.35) |
| 2.3 Eraser | per-objek, mode target, ukuran, undo | `Rendering/InkCanvasView.swift` |
| 2.4 Lasso | pilih, pindah, hapus, gandakan | `Rendering/InkCanvasView.swift` |
| 2.5 Shape recognition | garis, panah, persegi, elips, segitiga, belah ketupat | `Core/ShapeRecognizer.swift` |
| 2.8 Layers | tambah, urut, kunci, sembunyikan, hapus | `UI/LayerPanel.swift` |
| 2.9 Kualitas | palm rejection, koalesensi, autosave, undo | `Rendering/InkCanvasView.swift` |
| 3.1–3.3 Notebook/folder/halaman | CRUD, trash, duplikat, putar, urut | `Core/NotebookManager.swift`, `App/LibraryView.swift` |
| 3.4 Paper templates | 22 template dirender vektor | `Core/TemplateSpec.swift`, `Rendering/TemplateRenderer.swift` |
| 3.6 Navigasi | daftar halaman, lompat | `UI/EditorView.swift` |
| 4.1–4.5 PDF | impor, baca, anotasi, ekspor dengan opsi | `PDF/PDFImporter.swift`, `PDF/PDFExporter.swift` |
| 6.1 Pencarian | FTS5 lintas notebook, teks, PDF, tulisan tangan | `Search/SearchIndex.swift` |
| 6.2 Handwriting recognition | Vision OCR + tautan ke posisi | `Search/SearchIndex.swift` |
| 7.1–7.4 Audio | rekam, transkrip, ringkasan rapat, replay | `Audio/*`, `UI/AudioPanel.swift` |
| 8.1–8.4 Study | flashcard, mode belajar, SM-2, generator AI | `Study/Flashcard.swift`, `UI/StudyView.swift` |
| 9.1–9.4, 9.6 AI | ask, write, math, study, gambar | `AI/AIAssistant.swift`, `UI/AIPanel.swift` |
| 9.7 Kuota | batas bulanan, per fitur, gagal tidak memotong | `AI/UsageMeter.swift` |
| 16.2–16.6 Arsitektur | SwiftUI, stroke terstruktur, SQLite, PDFKit, Vision | seluruh `Sources/` |
| 17 Privasi | key di Keychain, lokal, hapus data | `AI/Keychain.swift`, `UI/SettingsView.swift` |

## Sebagian

| Spec | Status | Catatan |
|---|---|---|
| 2.4 Lasso | sebagian | Ubah ukuran dan rotasi objek belum ada handle transform; perpindahan sudah. |
| 2.6 Gesture-based editing | belum | Scribble-to-erase dan circle-to-lasso belum dipetakan ke gestur; alatnya ada, gestur pintasnya belum. |
| 2.7 Smart ink / restyle | belum | Butuh model khusus; di luar cakupan MVP. |
| 6.3 Math recognition | belum | Pengenalan ekspresi matematika dari tulisan belum; bantuan matematika lewat AI teks sudah ada. |
| 9.5 AI create mode | belum | Penulisan ke halaman lewat persetujuan belum dijahit; panel AI hanya menampilkan hasil. |
| 5.1–5.4 Teks, gambar, element, stiker | sebagian | Model data ada; toolbar insert objek ke halaman belum dipasang. |

## Belum dikerjakan (butuh server atau akun berbayar)

Sesuai keputusan awal: pemakaian pribadi, jadi fitur ini sengaja di luar cakupan.

| Spec | Alasan |
|---|---|
| 11 Cloud sync, backup | Butuh backend + akun |
| 12 Collaboration | Butuh server realtime, bukan kirim salinan |
| 13 Marketplace | Butuh backend, moderasi, lisensi |
| 15 Freemium, IAP, pembayaran | Butuh App Store Connect dan validasi transaksi di server |
| 16.7 Backend | Tidak ada server untuk versi pribadi ini |
| 10 Whiteboard | Kanvas tak terbatas belum dibangun; planner berbasis template sudah |

## Keterbatasan yang jujur

- **Belum dijalankan di perangkat atau simulator.** Lingkungan penulisan Linux tanpa Xcode.
  Verifikasi kompilasi dan test lewat CI macOS. Kalau CI merah, itu bug nyata — bukan
  diabaikan.
- **Tidak ada test UI.** 52 unit test menutup codec, penjadwalan SM-2, OCR grounding,
  shape recognition, kuota, dan operasi halaman. Alur layar belum diuji otomatis.
- **OCR tulisan tangan perlu halaman ter-render.** Kualitas bergantung Vision.
- **Embedding retrieval belum vektor.** Pencarian memakai FTS5 + skor leksikal; cukup untuk
  sitasi halaman, belum semantik penuh.
- **Satu halaman aktif per jendela.** Virtualisasi ratusan halaman ada di strip dan
  penyimpanan, bukan di render semua sekaligus.
