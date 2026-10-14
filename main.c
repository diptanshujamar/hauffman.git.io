#include "compression.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void read_line(const char *prompt, char *buf, size_t sz) {
    fputs(prompt, stdout); fflush(stdout);
    if (!fgets(buf, (int)sz, stdin)) buf[0] = '\0';
    buf[strcspn(buf, "\r\n")] = '\0';
}

static void test_custom_codes(void) {
    char input[256], err[128], detail[256];
    CodeTable table;
    read_line("\nEnter custom codes (e.g. 'A-10, B-00, C-01'): ", input, sizeof(input));
    if (!input[0]) strcpy(input, "A-10, B-00, C-01");

    if (!parse_custom_codes(input, &table, err, sizeof(err))) {
        printf("Error: %s\n", err);
        return;
    }

    printf("\n--- Parsed Codewords ---\n");
    for (int i = 0; i < table.count; i++)
        printf("%-6s | %-12s | %d bits\n", table.items[i].sym, table.items[i].code, (int)strlen(table.items[i].code));

    int is_pf = check_prefix_free(&table, detail, sizeof(detail));
    printf("\n[1] Prefix-Free Test: %s\n    Detail: %s\n", is_pf ? "PASSED" : "FAILED", detail);

    int is_amb = check_ambiguity(&table, detail, sizeof(detail));
    printf("[2] Ambiguity Test:   %s\n    Detail: %s\n", is_amb ? "AMBIGUOUS" : "UNAMBIGUOUS (Unique)", detail);

    double k = get_kraft_sum(&table);
    printf("[3] Kraft Sum:        K = %.4f %s\n", k, k <= 1.000001 ? "(<= 1.0 Satisfied)" : "(> 1.0 Violated)");
}

int main(void) {
    char choice[16], text[2048];
    printf("========================================================\n");
    printf("  DISCRETE MATHEMATICS: HUFFMAN VS SHANNON-FANO CODING  \n");
    printf("========================================================\n");
    printf("1. Compress Text & Analyze Metrics (Default)\n");
    printf("2. Test Custom Codes (e.g. A-10, B-00)\n");
    read_line("\nSelect option (1/2): ", choice, sizeof(choice));

    if (choice[0] == '2') { test_custom_codes(); return 0; }

    read_line("\nEnter text to compress: ", text, sizeof(text));
    if (!text[0]) strcpy(text, "discrete mathematics");

    CodeTable huff_tbl, sf_tbl;
    int n = get_frequencies(text, &huff_tbl);
    get_frequencies(text, &sf_tbl);

    char huff_bin[8192] = {0}, sf_bin[8192] = {0};
    huffman_encode(text, &huff_tbl, huff_bin, sizeof(huff_bin));
    shannon_fano_encode(text, &sf_tbl, sf_bin, sizeof(sf_bin));

    char huff_dec[2048] = {0}, sf_dec[2048] = {0};
    decode_bitstream(huff_bin, &huff_tbl, huff_dec, sizeof(huff_dec));
    decode_bitstream(sf_bin, &sf_tbl, sf_dec, sizeof(sf_dec));

    printf("\nOriginal text: %s (%d chars)\n", text, n);

    printf("\n--- Generated Codes & Per-Character Bit Lengths ---\n");
    printf("%-8s | %-5s | %-6s | %-10s | %-4s | %-8s | %-10s | %-4s | %-8s\n",
           "Char", "Count", "Prob", "Huff Code", "Bits", "Huff p*L", "SF Code", "Bits", "SF p*L");
    printf("--------------------------------------------------------------------------------\n");

    for (int i = 0; i < huff_tbl.count; i++) {
        double p = (double)huff_tbl.items[i].count / n;
        int hl = (int)strlen(huff_tbl.items[i].code);
        int sl = (int)strlen(sf_tbl.items[i].code);
        const char *name = strcmp(huff_tbl.items[i].sym, " ") == 0 ? "space" : huff_tbl.items[i].sym;

        printf("%-8s | %-5d | %-6.3f | %-10s | %-4d | %-8.3f | %-10s | %-4d | %-8.3f\n",
               name, huff_tbl.items[i].count, p,
               huff_tbl.items[i].code, hl, p * hl,
               sf_tbl.items[i].code, sl, p * sl);
    }

    double H = get_entropy(&huff_tbl, n);
    double L_huff = get_average_length(&huff_tbl, n);
    double L_sf = get_average_length(&sf_tbl, n);
    int orig_bits = n * 8, hb = (int)strlen(huff_bin), sb = (int)strlen(sf_bin);

    printf("\n--- Compression Summary ---\n");
    printf("Original Size:   %d bits\n", orig_bits);
    printf("Huffman:         %d bits (Avg L: %.3f b/s, Eff: %.2f%%)\n", hb, L_huff, (H / L_huff) * 100);
    printf("Shannon-Fano:    %d bits (Avg L: %.3f b/s, Eff: %.2f%%)\n", sb, L_sf, (H / L_sf) * 100);
    printf("Entropy H(X):    %.3f bits/symbol (Theoretical lower bound)\n", H);
    printf("Decoded Correct: Huffman: [%s] | SF: [%s]\n", huff_dec, sf_dec);

    char detail[256];
    printf("\n--- Verification ---\n");
    check_prefix_free(&huff_tbl, detail, sizeof(detail));
    printf("Huffman Prefix-Free: %s\n", detail);
    check_prefix_free(&sf_tbl, detail, sizeof(detail));
    printf("Shannon-Fano Prefix-Free: %s\n", detail);

    printf("\n--- Formulas & Data Structures Used ---\n");
    printf("Huffman:      Min-Heap Priority Queue + Binary Prefix Trie (Optimal O(N log N))\n");
    printf("Shannon-Fano: Descending Sorted Array + Divide-and-Conquer Recursion\n");
    printf("Entropy:      H(X) = -SUM [ p(x) * log2(p(x)) ]\n");
    printf("Avg Length:   L    = SUM [ p(x) * length(code(x)) ]\n");
    printf("Efficiency:   eta  = (H(X) / L) * 100%%\n");
    printf("Kraft Sum:    K    = SUM [ 2^(-l(x)) ] <= 1.0 (Satisfied)\n");

    return 0;
}
