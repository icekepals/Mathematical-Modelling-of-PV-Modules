%% MODEL MATEMATIKA PRODUKSI LISTRIK FOTOVOLTAIK (PV)
%  Tim Crisbar - MCF ITB 2026
%  Simulasi 50 Tahun ke Depan
%% 

clc; clear; close all;

%% BAGIAN 1: KONSTANTA TETAP

% Panel & Sistem
A        = 1.0;       % Luas permukaan aktif panel [m^2]
eta_ref  = 0.20;      % Efisiensi dasar pada kondisi STC [-]
mu_T     = -0.0045;   % Koefisien koreksi suhu efisiensi [/degC]
T_ref    = 25;        % Suhu referensi STC [degC]
NOCT     = 45;        % Nominal Operating Cell Temperature [degC]
Dr       = 0.005;     % Laju degradasi tahunan majemuk [/tahun]
P_rated  = 300;       % Daya nominal panel pada STC [W]

% Radiasi & Atmosfer
G_sc     = 1367;      % Konstanta surya [W/m^2]
tau_a    = 0.75;      % Transmitansi atmosfer langit cerah [-]
phi      = -6.8945;   % Lintang geografis [derajat] (ITB Ganesha, Bandung)
phi_rad  = phi * pi / 180;

% Debu 
L_dust_max = 0.15;    % Batas maksimum kehilangan akibat debu [-]
lambda_dust = 0.10;   % Laju akumulasi debu per hari [/hari]

% Downtime
L_down   = 0.02;      % Kehilangan akibat waktu henti sistem [-]

% Pemanasan Global
gamma    = 0.025;     % Laju pemanasan global [degC/tahun] (IPCC AR6, skenario moderat)
d_global = 1;         % Tanggal basis pemanasan global
m_global = 1;         % Bulan basis pemanasan global
y_global = 2026;      % Tahun basis pemanasan global

%% BAGIAN 2: VARIABEL INPUT PENGGUNA

% Tanggal referensi pemasangan sel PV
d_ref = 15;    % Tanggal pemasangan
m_ref = 3;     % Bulan pemasangan
y_ref = 2026;  % Tahun pemasangan

% Rentang simulasi
tahun_awal = y_ref;
tahun_akhir = y_ref + 49;  % 50 tahun ke depan

%% BAGIAN 3: FUNGSI-FUNGSI PEMODELAN

% Helper: konversi (day, month, year) -> day-of-year (1-365)
dayOfYear = @(dd, mm, yy) datenum(yy, mm, dd) - datenum(yy, 1, 0);

% Helper: hitung jumlah hari kumulatif sejak tanggal referensi
nDaysSinceRef = @(dd, mm, yy) datenum(yy, mm, dd) - datenum(y_ref, m_ref, d_ref);

%% BAGIAN 4: SIMULASI UTAMA

fprintf(' SIMULASI PRODUKSI ENERGI PV - 50 TAHUN\n');
fprintf(' Lokasi   : ITB Ganesha, Bandung (phi = %.4f deg)\n', phi);
fprintf(' Ref Pasang: %d-%d-%d\n', d_ref, m_ref, y_ref);
fprintf(' Periode  : %d - %d\n', tahun_awal, tahun_akhir);

% Pra-alokasi hasil
n_tahun = tahun_akhir - tahun_awal + 1;
E_tahunan   = zeros(1, n_tahun);   % Energi total per tahun [Wh]
E_harian_avg = zeros(1, n_tahun);  % Rata-rata energi harian per tahun [Wh/hari]

rng('shuffle');  % Seed acak berdasarkan waktu sistem

for idx_tahun = 1:n_tahun
    y = tahun_awal + idx_tahun - 1;
    fprintf('Simulasi tahun %d / %d (tahun ke-%d)...\n', y, tahun_akhir, idx_tahun);

    % Jumlah hari dalam tahun ini
    if mod(y,4)==0 && (mod(y,100)~=0 || mod(y,400)==0)
        n_hari = 366;
    else
        n_hari = 365;
    end

    E_hari_arr = zeros(1, n_hari);

    % Inisialisasi status debu untuk tahun ini
    delta_d = 0;  % Jumlah hari sejak hujan terakhir

    for d_in_year = 1:n_hari

        % Konversi hari ke tanggal (dd, mm)
        date_vec = datevec(datenum(y, 1, 0) + d_in_year);
        dd = date_vec(3);
        mm = date_vec(2);

        % Hari ke-d dalam tahun (1-365)
        d_year = d_in_year;

        % Bulan (1-12)
        m = mm;

        % Jumlah hari kumulatif sejak tanggal referensi [n]
        n_cum = nDaysSinceRef(dd, mm, y);

        % Umur sistem sejak pemasangan [tahun]
        t_tahun = n_cum / 365.25;
        if t_tahun < 0
            t_tahun = 0;
        end

        %% (A) MODEL CUACA STOKASTIK
        % epsilon: variabilitas cuaca harian ~ Uniform(0.75, 0.85)
        epsilon = 0.75 + (0.85 - 0.75) * rand();

        % Simulasi hujan: random [0,1] dibandingkan dengan p_rain(m)
        p_rain = 0.45 + 0.25 * cos(2*pi*(m-1)/12);
        r_hujan = rand();  % random [0,1]
        if r_hujan < p_rain
            delta_d = 0;   % Hari hujan -> reset debu
        else
            delta_d = delta_d + 1;  % Tidak hujan -> debu bertambah
        end

        %% (B) MODEL RADIASI SURYA
        % Sudut deklinasi matahari: delta(d) [derajat]
        delta_deg = 23.45 * sin((360/365) * (d_year - 81) * pi/180);
        delta_rad = delta_deg * pi / 180;

        % Integrasi numerik H(d) sepanjang 24 jam (step 0.1 jam)
        h_arr = 0:0.1:23.9;
        G_arr = zeros(size(h_arr));

        for k = 1:length(h_arr)
            h = h_arr(k);

            % Sudut jam: omega(h) [derajat]
            omega_deg = 15 * (h - 12);
            omega_rad = omega_deg * pi / 180;

            % Sudut elevasi matahari: alpha_s(h,d) [radian]
            sin_alpha = sin(phi_rad)*sin(delta_rad) + ...
                        cos(phi_rad)*cos(delta_rad)*cos(omega_rad);
            alpha_s = asin(max(-1, min(1, sin_alpha)));

            % Hanya integrasikan saat matahari di atas horizon
            if alpha_s > 0
                % Indeks kejernihan langit stokastik K_T(m,d)
                K_T_raw = 0.463 + 0.10*cos(2*pi*(m-8)/12) + 0.08*epsilon;
                K_T = max(0.1, min(1.0, K_T_raw));

                % Fraksi difus fd(K_T) - korelasi Erb's
                if K_T <= 0.22
                    f_d = 1 - 0.09*K_T;
                elseif K_T <= 0.80
                    f_d = 0.9511 - 0.1604*K_T + 4.388*K_T^2 ...
                          - 16.638*K_T^3 + 12.336*K_T^4;
                else
                    f_d = 0.165;
                end

                % Iradiasi total sesaat G_total [W/m^2]
                G_arr(k) = G_sc * tau_a * sin(alpha_s) * (K_T + f_d);
            end
        end

        % Radiasi harian H(d) dengan integrasi trapesoid [Wh/m^2]
        H_d = trapz(h_arr, G_arr);

        % Representatif G_total sesaat untuk perhitungan P (gunakan nilai jam siang)
        % Hitung G saat jam 12 (solar noon) untuk referensi L_inv
        omega_noon_rad = 0;
        sin_alpha_noon = sin(phi_rad)*sin(delta_rad) + ...
                         cos(phi_rad)*cos(delta_rad)*cos(omega_noon_rad);
        alpha_noon = asin(max(-1, min(1, sin_alpha_noon)));

        if alpha_noon > 0
            K_T_noon = 0.463 + 0.10*cos(2*pi*(m-8)/12) + 0.08*epsilon;
            K_T_noon = max(0.1, min(1.0, K_T_noon));
            if K_T_noon <= 0.22
                f_d_noon = 1 - 0.09*K_T_noon;
            elseif K_T_noon <= 0.80
                f_d_noon = 0.9511 - 0.1604*K_T_noon + 4.388*K_T_noon^2 ...
                           - 16.638*K_T_noon^3 + 12.336*K_T_noon^4;
            else
                f_d_noon = 0.165;
            end
            G_noon = G_sc * tau_a * sin(alpha_noon) * (K_T_noon + f_d_noon);
        else
            G_noon = 0;
        end

        %% (C) MODEL SUHU
        % Suhu ambien rata-rata harian (h=12 sebagai representatif siang)
        h_rep = 12;
        T_amb_h = 23 + 6*sin(2*pi*(h_rep - 6)/24) + gamma*t_tahun;

        % Suhu sel PV (NOCT model) menggunakan G_noon
        T_C = T_amb_h + ((NOCT - 20)/800) * G_noon;

        %% (D) MODEL EFISIENSI
        % eta(h,d,t) = eta_ref * (1 + mu_T*(T_C - T_ref)) * (1 - Dr)^t
        eta = eta_ref * (1 + mu_T*(T_C - T_ref)) * (1 - Dr)^t_tahun;
        eta = max(0, eta);  % Efisiensi tidak boleh negatif

        %% (E) MODEL PERFORMANCE RATIO
        % Hambatan Debu
        L_dust = L_dust_max * (1 - exp(-lambda_dust * delta_d));

        % Hambatan Inverter
        % Daya sesaat P = G_total * A * eta
        P_sesaat = G_noon * A * eta;
        ratio_P = P_sesaat / P_rated;

        if ratio_P < 0.10
            L_inv = 0.12;
        elseif ratio_P < 0.50
            L_inv = 0.06;
        else
            L_inv = 0.04;
        end

        % Performance Ratio
        PR = (1 - L_dust) * (1 - L_inv) * (1 - L_down);

        %% ---- (F) ENERGI HARIAN ----
        % E = A * eta * H(d) * PR  [Wh]
        E_hari = A * eta * H_d * PR;
        E_hari_arr(d_in_year) = max(0, E_hari);

    end % akhir loop hari

    % Simpan hasil tahunan
    E_tahunan(idx_tahun)    = sum(E_hari_arr);           % [Wh/tahun]
    E_harian_avg(idx_tahun) = mean(E_hari_arr);          % [Wh/hari rata-rata]

    fprintf('  -> E tahunan = %.2f Wh = %.4f kWh\n', ...
        E_tahunan(idx_tahun), E_tahunan(idx_tahun)/1000);

end % akhir loop tahun

%% BAGIAN 5: RATA-RATA KUMULATIF (E_avg)

% E_avg dari awal pemasangan hingga tahun ke-N
E_avg_kumulatif = zeros(1, n_tahun);
for i = 1:n_tahun
    E_avg_kumulatif(i) = mean(E_harian_avg(1:i));
end

%% BAGIAN 6: OUTPUT & VISUALISASI

tahun_arr = tahun_awal:tahun_akhir;

fprintf(' RINGKASAN HASIL SIMULASI\n');
fprintf(' Energi harian rata-rata tahun pertama : %.4f Wh\n', E_harian_avg(1));
fprintf(' Energi harian rata-rata tahun ke-50   : %.4f Wh\n', E_harian_avg(end));
fprintf(' Energi tahunan tahun pertama           : %.2f Wh (%.4f kWh)\n', ...
    E_tahunan(1), E_tahunan(1)/1000);
fprintf(' Energi tahunan tahun ke-50             : %.2f Wh (%.4f kWh)\n', ...
    E_tahunan(end), E_tahunan(end)/1000);
fprintf(' E_avg kumulatif 50 tahun               : %.4f Wh/hari\n', E_avg_kumulatif(end));

% Plot 1: Energi Tahunan
figure('Name','Energi Tahunan PV','NumberTitle','off');
plot(tahun_arr, E_tahunan/1000, 'b-o', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Tahun');
ylabel('Energi Tahunan (kWh)');
title('Proyeksi Energi Tahunan Sel PV - 50 Tahun');
grid on;
xlim([tahun_awal, tahun_akhir]);

% Plot 2: Energi Harian Rata-rata per Tahun
figure('Name','Energi Harian Rata-rata','NumberTitle','off');
plot(tahun_arr, E_harian_avg, 'r-s', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Tahun');
ylabel('Energi Harian Rata-rata (Wh/hari)');
title('Rata-rata Energi Harian Sel PV per Tahun');
grid on;
xlim([tahun_awal, tahun_akhir]);

% Plot 3: E_avg Kumulatif
figure('Name','E_avg Kumulatif','NumberTitle','off');
plot(tahun_arr, E_avg_kumulatif, 'g-^', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Tahun');
ylabel('E_{avg} kumulatif (Wh/hari)');
title('Rata-rata Energi Harian Kumulatif Sejak Pemasangan');
grid on;
xlim([tahun_awal, tahun_akhir]);

% Plot 4: Gabungan (subplot)
figure('Name','Ringkasan Simulasi PV 50 Tahun','NumberTitle','off');
subplot(3,1,1);
plot(tahun_arr, E_tahunan/1000, 'b-o', 'LineWidth', 1.5, 'MarkerSize', 3);
ylabel('Energi Tahunan (kWh)');
title('Proyeksi Produksi Energi PV - 50 Tahun ke Depan');
grid on; xlim([tahun_awal, tahun_akhir]);

subplot(3,1,2);
plot(tahun_arr, E_harian_avg, 'r-s', 'LineWidth', 1.5, 'MarkerSize', 3);
ylabel('E_{hari} rata-rata (Wh/hari)');
grid on; xlim([tahun_awal, tahun_akhir]);

subplot(3,1,3);
plot(tahun_arr, E_avg_kumulatif, 'g-^', 'LineWidth', 1.5, 'MarkerSize', 3);
xlabel('Tahun');
ylabel('E_{avg} kumulatif (Wh/hari)');
grid on; xlim([tahun_awal, tahun_akhir]);

%% BAGIAN 7: SIMPAN DATA KE FILE CSV

output_data = [tahun_arr', E_tahunan'/1000, E_harian_avg', E_avg_kumulatif'];
fid = fopen('hasil_simulasi_PV.csv', 'w');
fprintf(fid, 'Tahun,E_Tahunan_kWh,E_Harian_avg_Wh,E_avg_kumulatif_Wh\n');
for i = 1:n_tahun
    fprintf(fid, '%d,%.6f,%.6f,%.6f\n', ...
        output_data(i,1), output_data(i,2), output_data(i,3), output_data(i,4));
end
fclose(fid);
fprintf('Data hasil simulasi disimpan ke: hasil_simulasi_PV.csv\n');
