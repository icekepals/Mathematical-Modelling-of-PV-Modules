%% MODEL MATEMATIKA PRODUKSI LISTRIK FOTOVOLTAIK (PV)
%  Tim Crisbar - MCF ITB 2026
%  Simulasi 50 Tahun ke Depan
%%

clc; clear; close all;

%% BAGIAN 1: KONSTANTA TETAP

% Panel & Sistem
A          = 1.0;       % Luas permukaan aktif panel [m^2]
eta_ref    = 0.20;      % Efisiensi dasar pada kondisi STC [-]
mu_T       = -0.0045;   % Koefisien koreksi suhu efisiensi [/degC]
T_ref      = 25.0;      % Suhu referensi STC [degC]
NOCT       = 45.0;      % Nominal Operating Cell Temperature [degC]
Dr         = 0.005;     % Laju degradasi tahunan majemuk [/tahun]
P_rated    = 300.0;     % Daya nominal panel pada STC [W]

% Radiasi & Atmosfer
G_sc       = 1367.0;    % Konstanta surya [W/m^2]
tau_a      = 0.75;      % Transmitansi atmosfer langit cerah [-]
phi        = -6.8945;   % Lintang geografis [derajat] (ITB Ganesha, Bandung)
phi_rad    = phi * pi / 180;

% Debu
L_dust_max  = 0.15;     % Batas maksimum kehilangan akibat debu [-]
lambda_dust = 0.10;     % Laju akumulasi debu per hari [/hari]

% Downtime
L_down     = 0.02;      % Kehilangan akibat waktu henti sistem [-]

% Pemanasan Global
gamma      = 0.025;     % Laju pemanasan global [degC/tahun] (IPCC AR6, skenario moderat)

%% BAGIAN 2: VARIABEL INPUT PENGGUNA

% Tanggal referensi pemasangan sel PV
d_ref = 1;      % Tanggal pemasangan
m_ref = 1;      % Bulan pemasangan
y_ref = 2026;   % Tahun pemasangan

% Jumlah langkah integrasi per hari
N_steps = 48;
dh      = 24.0 / N_steps;

% Rentang simulasi
tahun_awal  = y_ref;
tahun_akhir = y_ref + 49;  % 50 tahun ke depan
n_tahun     = tahun_akhir - tahun_awal + 1;

%% BAGIAN 3: KONVERSI TANGGAL & PRA-HITUNG DEBU

install_serial = datenum(y_ref, m_ref, d_ref);
end_serial     = datenum(y_ref + n_tahun, m_ref, d_ref) - 1;
N_total        = end_serial - install_serial + 1;

fprintf(' SIMULASI PRODUKSI ENERGI PV - 50 TAHUN\n');
fprintf(' Lokasi    : ITB Ganesha, Bandung (phi = %.4f deg)\n', phi);
fprintf(' Ref Pasang: %02d-%02d-%04d\n', d_ref, m_ref, y_ref);
fprintf(' Periode   : %d - %d\n\n', tahun_awal, tahun_akhir);

% Pra-hitung debu untuk semua hari simulasi
% Gambar 2.13: L_dust = L_dust_max * (1 - exp(-lambda * delta_d))
% Gambar 2.14: p_rain(m) = 0.45 + 0.25*cos(2pi*(m-1)/12)
fprintf(' Pra-hitung debu untuk %d hari...\n', N_total);
dust_all = zeros(1, N_total);
delta_d  = 0;

for i = 1 : N_total
    cur_serial  = install_serial + (i - 1);
    cur_vec     = datevec(cur_serial);
    cur_year_d  = cur_vec(1);
    cur_month_d = cur_vec(2);
    cur_day_d   = cur_vec(3);

    % p_rain(m) — Gambar 2.14
    p_rain_i = 0.45 + 0.25 * cos(2*pi*(cur_month_d - 1) / 12);

    % Seed deterministik per tanggal (+1 agar berbeda dari seed KT)
    rain_seed = cur_year_d * 10000 + cur_month_d * 100 + cur_day_d + 1;
    rng(rain_seed);

    if rand() < p_rain_i
        delta_d = 0;           % Hari hujan -> reset debu
    else
        delta_d = delta_d + 1; % Tidak hujan -> debu bertambah
    end

    % L_dust(d) — Gambar 2.13
    dust_all(i) = L_dust_max * (1 - exp(-lambda_dust * delta_d));
end

%% BAGIAN 4: SIMULASI UTAMA

% Pra-alokasi hasil
E_tahunan    = zeros(1, n_tahun);
E_harian_avg = zeros(1, n_tahun);
eta_avg_thn  = zeros(1, n_tahun);
H_avg_thn    = zeros(1, n_tahun);
PR_avg_thn   = zeros(1, n_tahun);

fprintf('\n Tahun  | E_thn(kWh)  | E_hr(Wh)   | H_avg(Wh/m2) | eta_avg  | PR_avg\n');

day_counter = 0;

for idx_tahun = 1 : n_tahun

    y = tahun_awal + idx_tahun - 1;

    % Jumlah hari dalam tahun ini
    if mod(y, 4) == 0 && (mod(y, 100) ~= 0 || mod(y, 400) == 0)
        n_hari = 366;
    else
        n_hari = 365;
    end

    % Akumulator level tahun
    E_thn_sum   = 0.0;
    H_sum_thn   = 0.0;
    eta_sum_thn = 0.0;
    PR_sum_thn  = 0.0;
    n_active    = 0;

    for d_in_year = 1 : n_hari

        day_counter = day_counter + 1;

        % Info tanggal hari ini
        cur_serial  = install_serial + (day_counter - 1);
        cur_vec     = datevec(cur_serial);
        cur_year    = cur_vec(1);
        cur_month   = cur_vec(2);
        cur_day     = cur_vec(3);

        % Umur sistem sejak pemasangan [tahun]
        t_tahun = (day_counter - 1) / 365.25;

        % Hari ke-d dalam tahun
        jan1_serial = datenum(cur_year, 1, 1);
        d_year      = cur_serial - jan1_serial + 1;

        %% (A) MODEL CUACA STOKASTIK
        % epsilon ~ N(0,1), Box-Muller, seed deterministik per tanggal
        kt_seed = cur_year * 10000 + cur_month * 100 + cur_day;
        rng(kt_seed);
        u1    = rand();  u2 = rand();
        eps_i = sqrt(-2 * log(u1)) * cos(2*pi*u2);

        % Indeks kejernihan langit K_T(m,d) — Gambar 2.10
        K_T = 0.463 + 0.10*cos(2*pi*(cur_month - 8)/12) + 0.08*eps_i;
        K_T = max(0.1, min(1.0, K_T));

        % Debu hari ini — Gambar 2.13
        L_dust = dust_all(day_counter);

        %% (B) MODEL RADIASI SURYA
        % Sudut deklinasi matahari — Gambar 2.8
        delta_deg = 23.45 * sin((360/365) * (d_year - 81) * pi/180);
        delta_rad = delta_deg * pi / 180;

        % Fraksi difus fd(K_T) — Gambar 2.11, korelasi Erb's
        if K_T <= 0.22
            f_d = 1 - 0.09*K_T;
        elseif K_T <= 0.80
            f_d = 0.9511 - 0.1604*K_T + 4.388*K_T^2 - 16.638*K_T^3 + 12.336*K_T^4;
        else
            f_d = 0.165;
        end

        % Integrasi energi harian per langkah waktu
        E_hari  = 0.0;
        H_i     = 0.0;
        eta_w_i = 0.0;
        PR_w_i  = 0.0;
        G_w_i   = 0.0;

        for step = 1 : N_steps
            h = (step - 1) * dh;

            % Sudut jam — Gambar 2.9
            omega_rad = 15 * (h - 12) * pi/180;

            % Sudut elevasi matahari — Gambar 2.7
            sin_alpha = sin(phi_rad)*sin(delta_rad) + ...
                        cos(phi_rad)*cos(delta_rad)*cos(omega_rad);
            alpha_s   = asin(max(-1.0, min(1.0, sin_alpha)));

            if alpha_s <= 0
                continue;
            end

            % Iradiasi total sesaat G_total — Gambar 2.6
            G_step = G_sc * tau_a * sin(alpha_s) * (K_T + f_d);

            if G_step <= 0
                continue;
            end

            %% (C) MODEL SUHU
            % Suhu ambien sesaat — Gambar 2.4
            T_amb = 23 + 6*sin(2*pi*(h - 6)/24) + gamma*t_tahun;

            % Suhu sel PV — Gambar 2.3
            T_C = T_amb + ((NOCT - 20)/800) * G_step;

            %% (D) MODEL EFISIENSI
            % eta = eta_ref * (1 + mu_T*(T_C - T_ref)) * (1 - Dr)^t — Gambar 2.2
            eta = eta_ref * (1 + mu_T*(T_C - T_ref)) * (1 - Dr)^t_tahun;
            eta = max(0, eta);

            %% (E) MODEL PERFORMANCE RATIO
            % Hambatan Inverter — Gambar 2.15 & 2.16
            P_sesaat = G_step * A * eta;
            ratio_P  = P_sesaat / P_rated;

            if ratio_P < 0.10
                L_inv = 0.12;
            elseif ratio_P < 0.50
                L_inv = 0.06;
            else
                L_inv = 0.04;
            end

            % Performance Ratio — Gambar 2.12
            PR = (1 - L_dust) * (1 - L_inv) * (1 - L_down);

            %% (F) KONTRIBUSI ENERGI SESAAT
            % dE = A * eta * G * PR * dh — Gambar 2.1
            E_hari  = E_hari  + A * eta * G_step * PR * dh;

            % Akumulasi diagnostik (rata-rata tertimbang G)
            H_i     = H_i     + G_step * dh;
            eta_w_i = eta_w_i + eta   * G_step * dh;
            PR_w_i  = PR_w_i  + PR    * G_step * dh;
            G_w_i   = G_w_i   + G_step * dh;

        end % akhir loop step

        E_hari = max(0, E_hari);

        % Akumulasi ke level tahun
        E_thn_sum = E_thn_sum + E_hari;
        H_sum_thn = H_sum_thn + H_i;

        if G_w_i > 0
            eta_sum_thn = eta_sum_thn + (eta_w_i / G_w_i);
            PR_sum_thn  = PR_sum_thn  + (PR_w_i  / G_w_i);
            n_active    = n_active + 1;
        end

    end % akhir loop hari

    % Simpan hasil tahunan
    E_tahunan(idx_tahun)    = E_thn_sum;
    E_harian_avg(idx_tahun) = E_thn_sum / n_hari;
    H_avg_thn(idx_tahun)    = H_sum_thn / n_hari;

    if n_active > 0
        eta_avg_thn(idx_tahun) = eta_sum_thn / n_active;
        PR_avg_thn(idx_tahun)  = PR_sum_thn  / n_active;
    end

    fprintf(' %-6d | %-11.4f | %-10.4f | %-12.2f | %-8.5f | %.4f\n', ...
            y, ...
            E_tahunan(idx_tahun) / 1000, ...
            E_harian_avg(idx_tahun), ...
            H_avg_thn(idx_tahun), ...
            eta_avg_thn(idx_tahun), ...
            PR_avg_thn(idx_tahun));

end % akhir loop tahun

%% BAGIAN 5: RATA-RATA KUMULATIF (E_avg)

% E_avg dari awal pemasangan hingga akhir tiap tahun — Gambar 2.2
E_avg_kumulatif = zeros(1, n_tahun);
total_E = 0.0;
total_d = 0;

for i = 1 : n_tahun
    y_i = tahun_awal + (i - 1);
    if mod(y_i,4)==0 && (mod(y_i,100)~=0 || mod(y_i,400)==0)
        n_hari_i = 366;
    else
        n_hari_i = 365;
    end
    total_E = total_E + E_tahunan(i);
    total_d = total_d + n_hari_i;
    E_avg_kumulatif(i) = total_E / total_d;
end

%% BAGIAN 6: OUTPUT & VISUALISASI

tahun_arr = tahun_awal : tahun_akhir;

fprintf('\n RINGKASAN HASIL SIMULASI\n');
fprintf(' Energi harian rata-rata tahun pertama : %.4f Wh\n', E_harian_avg(1));
fprintf(' Energi harian rata-rata tahun ke-50   : %.4f Wh\n', E_harian_avg(end));
fprintf(' Energi tahunan tahun pertama           : %.2f Wh (%.4f kWh)\n', ...
    E_tahunan(1), E_tahunan(1)/1000);
fprintf(' Energi tahunan tahun ke-50             : %.2f Wh (%.4f kWh)\n', ...
    E_tahunan(end), E_tahunan(end)/1000);
fprintf(' E_avg kumulatif 50 tahun               : %.4f Wh/hari\n', E_avg_kumulatif(end));
fprintf(' Penurunan E tahun ke-1 ke tahun ke-50  : %.2f%%\n', ...
    (E_tahunan(end) - E_tahunan(1)) / E_tahunan(1) * 100);

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
figure('Name','E avg Kumulatif','NumberTitle','off');
plot(tahun_arr, E_avg_kumulatif, 'g-^', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Tahun');
ylabel('E_{avg} kumulatif (Wh/hari)');
title('Rata-rata Energi Harian Kumulatif Sejak Pemasangan');
grid on;
xlim([tahun_awal, tahun_akhir]);

% Plot 4: Diagnostik eta, H, PR
figure('Name','Diagnostik eta - H - PR','NumberTitle','off');
subplot(3,1,1);
plot(tahun_arr, eta_avg_thn, 'm-o', 'LineWidth', 1.5, 'MarkerSize', 3);
ylabel('\eta rata-rata [-]');
title('Diagnostik Komponen per Tahun');
grid on; xlim([tahun_awal, tahun_akhir]);

subplot(3,1,2);
plot(tahun_arr, H_avg_thn, 'b-s', 'LineWidth', 1.5, 'MarkerSize', 3);
ylabel('H rata-rata [Wh/m^2/hari]');
grid on; xlim([tahun_awal, tahun_akhir]);

subplot(3,1,3);
plot(tahun_arr, PR_avg_thn, 'r-^', 'LineWidth', 1.5, 'MarkerSize', 3);
xlabel('Tahun');
ylabel('PR rata-rata [-]');
grid on; xlim([tahun_awal, tahun_akhir]);

% Plot 5: Gabungan (subplot)
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

output_data = [tahun_arr', E_tahunan'/1000, E_harian_avg', E_avg_kumulatif', ...
               eta_avg_thn', H_avg_thn', PR_avg_thn'];
fid = fopen('hasil_simulasi_PV.csv', 'w');
fprintf(fid, 'Tahun,E_Tahunan_kWh,E_Harian_avg_Wh,E_avg_kumulatif_Wh,eta_avg,H_avg_Wh_m2,PR_avg\n');
for i = 1 : n_tahun
    fprintf(fid, '%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n', ...
        output_data(i,1), output_data(i,2), output_data(i,3), ...
        output_data(i,4), output_data(i,5), output_data(i,6), output_data(i,7));
end
fclose(fid);
fprintf(' Data hasil simulasi disimpan ke: hasil_simulasi_PV.csv\n');
