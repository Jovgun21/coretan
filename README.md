# Coretan

Aplikasi digital note-taking premium untuk iPad, dibangun native dengan SwiftUI + PencilKit +
PDFKit + Vision. Local-first: catatan, tinta, audio dan PDF disimpan di perangkat, bukan di server.

## Status

Tahap 1 (MVP) selesai di kode; Tahap 2 sebagian. Lihat `docs/IMPLEMENTATION.md` untuk peta
fitur-vs-spec dan keterbatasan yang masih ada.

Belum diverifikasi di perangkat: proyek ini ditulis di lingkungan Linux tanpa Xcode, jadi
kompilasi dan jalannya aplikasi diverifikasi lewat CI macOS (`.github/workflows/ios.yml`),
bukan diklaim jalan tanpa bukti.

## Yang sudah berfungsi

**Tulisan tangan**
- Pen, highlighter, pencil: warna, ketebalan, preset tersimpan
- Pressure + tilt sensitivity, palm rejection, koalesensi touch untuk garis halus
- Eraser dengan target (tinta saja / highlighter saja / semua) + undo
- Lasso: pilih, pindah, ubah ukuran lewat transform, salin, potong, gandakan, hapus
- Shape recognition: garis, panah, persegi, elips, segitiga, belah ketupat
- Layer: tambah, urut, kunci, sembunyikan, ubah nama, hapus
- Zoom/pan di scroll view terpisah, jadi posisi objek relatif tidak berubah
- Autosave 0,8 detik setelah goresan terakhir + thumbnail per halaman
- Undo/redo berbasis operasi, bukan snapshot

**Dokumen**
- Notebook, folder bertingkat, favorit, urut nama/tanggal, cari, gandakan, trash
- Halaman: tambah, hapus, gandakan, pindah, putar, multi-pilih
- 22 template halaman dirender vektor (ruled, grid, dot, Cornell, music, planner, habit, dll.)
- Impor PDF jadi latar halaman yang di-cache; anotasi tetap lapisan terpisah
- Ekspor PDF: pilih halaman/rentang, sertakan atau tidak anotasi, pilihan skala render
- Format `.ctnk` biner sendiri, round-trip lossless untuk tiap goresan

**Pencarian dan pengenalan**
- FTS5 atas teks diketik, teks PDF, dan tulisan tangan hasil OCR
- OCR tulisan tangan lewat Vision, hasilnya dipetakan ke posisi di halaman

**Audio**
- Rekam kuliah: mulai/jeda/lanjut/stop, level meter, durasi
- Transkripsi dengan timestamp per segmen, lompat ke segmen dari transkrip
- Catatan rapat: topik, keputusan, action items — atau "tidak disebutkan" kalau transkrip kosong
- Note Replay: peta waktu-goresan untuk memutar ulang proses menulis

**Belajar**
- Flashcard + SM-2 spaced repetition, sesi harian, kartu gagal diulang di sesi yang sama
- Generator kartu AI: definisi, rumus, konsep, latihan — selalu lewat pratinjau dulu

**AI**
- Klien OpenAI-compatible: base URL, model chat/transkripsi/gambar bisa diatur
- Ask AI dengan rujukan halaman ke catatan pengguna sendiri
- Writing assistant: tata bahasa, ejaan, ringkas, perluas, poin, kerangka belajar
- Math assistant: langkah demi langkah, dan berhenti kalau tidak yakin
- Study assistant: ringkasan bab, konsep kunci, latihan, pilihan ganda, uraian, kuis
- Manajemen kuota: batas bulanan, pemakaian per fitur, request gagal tidak memotong kuota

**Privasi**
- API key di Keychain, bukan di bundle
- Tidak ada kredensial di kode; permintaan AI hanya keluar saat tombol ditekan
- Hapus semua data tersedia di Pengaturan

## Struktur

```
Sources/Coretan/
├── App/         CoretanApp, ContentView, LibraryView
├── Core/        model, penyimpanan SQLite, codec tinta, undo, shape recognition
├── Rendering/   InkCanvasView, TemplateRenderer, StrokeRenderer
├── UI/          Editor, palette, layer, audio, AI, study, search, settings, export
├── PDF/         importer + exporter
├── Search/      indeks FTS5 + OCR
├── Audio/       recorder + note replay
├── Study/       flashcard + SM-2
└── AI/          client, keychain, usage meter, RAG, assistant
Tests/CoretanTests/   52 unit test
```

Editor dipisah dari sistem dokumen dan dari backend, sesuai spec bagian 20.

## Build

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open Coretan.xcodeproj
```

CI: push ke `main` → GitHub Actions macOS runner build, jalankan test, lalu publish
`Coretan-unsigned.ipa` sebagai artifact. Untuk `.ipa` yang bisa langsung diinstal,
jalankan workflow "Signed IPA" setelah mengisi empat secret sertifikat.

## Menyambungkan AI

Buka Pengaturan, isi Base URL server OpenAI-compatible, model, dan API key.
Secara default diarahkan ke endpoint lokal, bukan layanan berbayar.

## Lisensi

Kode ini milik pemilik repo. Tidak dibangun dari aset, ikon, atau kode Goodnotes mana pun;
merek, nama, ikon dan desain ditentukan sendiri.
