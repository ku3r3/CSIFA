Hari 1: Fondasi, Respons Insiden, & Kesiapan Forensik
Fokus: Membangun pola pikir (mindset) seorang analis forensik dan penanggap pertama.
team01 : 0Kd/VpZ6fuvDHNQ5
team02 : OyQQftlEpyOyYj2V
instructor : SbFixE8LfI7x8+gc


    Pagi (Teori & Konsep):
        Bab 1: Konsep Esensial Forensik Komputer & Bab 6: Prinsip Bukti Digital.
        Bab 5: Peran Penanggap Pertama (First Responder) & Kesalahan Umum.
    Siang (Teori & Proses):
        Bab 2: Proses Penanganan dan Tanggapan Insiden (NIST Guidelines).
        Bab 4: Kesiapan Forensik (Forensic Readiness) & Kebijakan Retensi Data.
    Praktikum (Lab 1 - VPS Debian 13): 
        Topik: Live Response & Volatile Data Collection.
        Aktivitas: Peserta SSH ke VPS Debian 13. Mereka harus menjalankan perintah untuk mengumpulkan data volatil sebelum "sistem dimatikan" (simulasi). 
        Perintah Kunci: ps aux, netstat -tulpn / ss -tulpn, w, last, cat /proc/meminfo.
        Tantangan CTF Hari 1: Temukan "Flag 1" yang tersembunyi di dalam output perintah history atau di variabel lingkungan (env) pengguna yang mencurigakan.

Hari 2: Pengumpulan, Akuisisi, & Pengamanan Bukti Digital
Fokus: Teknik teknis pengambilan bukti tanpa merusak integritas (Chain of Custody).

    Pagi (Teori):
        Bab 7: Pengumpulan Bukti Digital (Urutan Volatilitas / Order of Volatility).
        Bab 8: Menyimpan dan Mengamankan Bukti Digital (Packing, Transport, Storage).
    Siang (Teori & Teknik):
        Bab 9: Metode Akuisisi Data (Live vs Static, Forensic Imaging, Hashing).
    Praktikum (Lab 2 - VPS Debian 13):
        Topik: Static Data Acquisition & Integrity Verification.
        Aktivitas: 
            Membuat disk image dari sebuah file loopback atau partisi simulasi di Debian menggunakan dd atau dcfldd.
            Menghitung dan memverifikasi hash (MD5/SHA-256) menggunakan md5sum atau sha256sum.
            Simulasi dokumentasi Chain of Custody (peserta mengisi formulir log akuisisi).
        Tantangan CTF Hari 2: Temukan "Flag 2" yang tersembunyi di dalam unallocated space dari file image yang baru dibuat, atau temukan file yang atributnya disembunyikan (hidden file) menggunakan ls -la atau stat.

Hari 3: Analisis Bukti, Anti-Forensik, & Pelaporan
Fokus: Menganalisis data, mengalahkan teknik penyembunyian, dan menyajikan temuan.

    Pagi (Teori & Analisis):
        Bab 3: Proses Investigasi Forensik Komputer.
        Bab 10: Analisis Bukti & Mengalahkan Teknik Anti-Forensik (Data Wiping, Encryption, Log Tampering).
    Siang (Praktikum Puncak & Penutup):
        Topik: Forensic Analysis & Mini CTF Final.
        Aktivitas: 
            Analisis Log: Mengecek /var/log/auth.log, /var/log/syslog, atau log firewall (sesuai memori: Firewall adalah komponen yang dibutuhkan untuk mengamankan jaringan).
            Pemulihan File: Menggunakan alat seperti extundelete atau photorec (jika diinstal) untuk memulihkan file yang "dihapus" oleh penyerang.
        Tantangan CTF Final (Grand Scenario): VPS Debian 13 telah "diserang". Peserta harus menemukan 3 hal: (a) IP Address penyerang dari log, (b) Nama file rahasia yang dienkripsi/di-hide, dan (c) Timestamp tepat saat serangan terjadi.
        Penutup: Bab 10 (Reporting) - Peserta menyusun laporan insiden singkat berdasarkan temuan CTF mereka.
