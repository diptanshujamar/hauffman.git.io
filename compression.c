#include "compression.h"
#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//UTF-8 & Frequency Counting 
static int utf8_len(const char *s) {
    unsigned char c = (unsigned char)*s;
    if (c < 0x80) return 1;
    if ((c & 0xE0) == 0xC0) return 2;
    if ((c & 0xF0) == 0xE0) return 3;
    if ((c & 0xF8) == 0xF0) return 4;
    return 1;
}

int get_frequencies(const char *text, CodeTable *table) {
    const char *p = text;
    int total_chars = 0;
    table->count = 0;

    while (*p) {
        char ch[SYM_LEN] = {0};
        int len = utf8_len(p);
        memcpy(ch, p, len);
        p += len;
        total_chars++;

        int found = -1;
        for (int i = 0; i < table->count; i++) {
            if (strcmp(table->items[i].sym, ch) == 0) { found = i; break; }
        }
        if (found >= 0) {
            table->items[found].count++;
        } else if (table->count < MAX_SYMS) {
            strncpy(table->items[table->count].sym, ch, SYM_LEN - 1);
            table->items[table->count].count = 1;
            table->items[table->count].code[0] = '\0';
            table->count++;
        }
    }
    return total_chars;
}

// Tree Helpers 
static TreeNode *new_node(const char *sym, int freq) {
    TreeNode *n = (TreeNode *)calloc(1, sizeof(TreeNode));
    if (sym) { strncpy(n->sym, sym, SYM_LEN - 1); n->is_leaf = 1; }
    n->freq = freq;
    return n;
}

void free_tree(TreeNode *root) {
    if (!root) return;
    free_tree(root->left);
    free_tree(root->right);
    free(root);
}

int get_tree_depth(const TreeNode *root) {
    if (!root) return 0;
    int l = get_tree_depth(root->left);
    int r = get_tree_depth(root->right);
    return 1 + (l > r ? l : r);
}

/* ---------- Huffman Algorithm ---------- */
static void huffman_dfs(TreeNode *node, char *path, int depth, CodeTable *table) {
    if (!node) return;
    if (node->is_leaf) {
        path[depth] = '\0';
        for (int i = 0; i < table->count; i++) {
            if (strcmp(table->items[i].sym, node->sym) == 0) {
                strncpy(table->items[i].code, (depth == 0) ? "0" : path, CODE_LEN - 1);
                break;
            }
        }
        return;
    }
    path[depth] = '0'; huffman_dfs(node->left, path, depth + 1, table);
    path[depth] = '1'; huffman_dfs(node->right, path, depth + 1, table);
}

void huffman_encode(const char *text, CodeTable *table, char *out_bin, size_t out_sz) {
    if (table->count == 0) { if (out_bin && out_sz) out_bin[0] = '\0'; return; }

    TreeNode *q[MAX_SYMS];
    int q_size = table->count;
    for (int i = 0; i < q_size; i++) q[i] = new_node(table->items[i].sym, table->items[i].count);

    if (q_size == 1) {
        TreeNode *root = new_node(NULL, q[0]->freq);
        root->left = q[0];
        q[0] = root;
    } else {
        while (q_size > 1) {
            /* Sort by frequency ascending (stable) */
            for (int i = 0; i < q_size - 1; i++) {
                for (int j = 0; j < q_size - i - 1; j++) {
                    if (q[j]->freq > q[j + 1]->freq) {
                        TreeNode *tmp = q[j]; q[j] = q[j + 1]; q[j + 1] = tmp;
                    }
                }
            }
            TreeNode *left = q[0], *right = q[1];
            for (int i = 2; i < q_size; i++) q[i - 2] = q[i];
            q_size -= 2;

            TreeNode *merged = new_node(NULL, left->freq + right->freq);
            merged->left = left; merged->right = right;
            q[q_size++] = merged;
        }
    }

    char path[CODE_LEN] = {0};
    huffman_dfs(q[0], path, 0, table);
    free_tree(q[0]);

    if (out_bin && out_sz) {
        out_bin[0] = '\0';
        const char *p = text;
        while (*p) {
            char ch[SYM_LEN] = {0};
            int len = utf8_len(p);
            memcpy(ch, p, len);
            p += len;
            for (int i = 0; i < table->count; i++) {
                if (strcmp(table->items[i].sym, ch) == 0) {
                    strncat(out_bin, table->items[i].code, out_sz - strlen(out_bin) - 1);
                    break;
                }
            }
        }
    }
}

//Shannon-Fano Algorithm 
typedef struct { char sym[SYM_LEN]; int freq; } SFSym;

static void sf_divide(SFSym *arr, int count, CodeTable *table) {
    if (count <= 1) return;
    int total = 0, left_sum = 0, split = 1, min_d;
    for (int i = 0; i < count; i++) total += arr[i].freq;
    min_d = total;

    for (int i = 0; i < count - 1; i++) {
        left_sum += arr[i].freq;
        int d = abs(left_sum - (total - left_sum));
        if (d < min_d) { min_d = d; split = i + 1; }
    }

    for (int i = 0; i < split; i++) {
        for (int k = 0; k < table->count; k++) {
            if (strcmp(table->items[k].sym, arr[i].sym) == 0)
                strncat(table->items[k].code, "0", CODE_LEN - strlen(table->items[k].code) - 1);
        }
    }
    for (int i = split; i < count; i++) {
        for (int k = 0; k < table->count; k++) {
            if (strcmp(table->items[k].sym, arr[i].sym) == 0)
                strncat(table->items[k].code, "1", CODE_LEN - strlen(table->items[k].code) - 1);
        }
    }
    sf_divide(arr, split, table);
    sf_divide(arr + split, count - split, table);
}

void shannon_fano_encode(const char *text, CodeTable *table, char *out_bin, size_t out_sz) {
    if (table->count == 0) { if (out_bin && out_sz) out_bin[0] = '\0'; return; }
    for (int i = 0; i < table->count; i++) table->items[i].code[0] = '\0';

    if (table->count == 1) {
        strcpy(table->items[0].code, "0");
    } else {
        SFSym arr[MAX_SYMS];
        for (int i = 0; i < table->count; i++) {
            strcpy(arr[i].sym, table->items[i].sym);
            arr[i].freq = table->items[i].count;
        }
        /* Sort descending */
        for (int i = 0; i < table->count - 1; i++) {
            for (int j = 0; j < table->count - i - 1; j++) {
                if (arr[j].freq < arr[j + 1].freq) {
                    SFSym tmp = arr[j]; arr[j] = arr[j + 1]; arr[j + 1] = tmp;
                }
            }
        }
        sf_divide(arr, table->count, table);
    }

    if (out_bin && out_sz) {
        out_bin[0] = '\0';
        const char *p = text;
        while (*p) {
            char ch[SYM_LEN] = {0};
            int len = utf8_len(p);
            memcpy(ch, p, len);
            p += len;
            for (int i = 0; i < table->count; i++) {
                if (strcmp(table->items[i].sym, ch) == 0) {
                    strncat(out_bin, table->items[i].code, out_sz - strlen(out_bin) - 1);
                    break;
                }
            }
        }
    }
}

//Bitstream Decoding
void decode_bitstream(const char *binary, const CodeTable *table, char *out_txt, size_t out_sz) {
    if (!out_txt || out_sz == 0) return;
    out_txt[0] = '\0';
    char cur[CODE_LEN] = {0};
    int clen = 0;

    for (const char *b = binary; *b; b++) {
        if (clen < CODE_LEN - 1) cur[clen++] = *b;
        cur[clen] = '\0';
        for (int i = 0; i < table->count; i++) {
            if (strcmp(table->items[i].code, cur) == 0) {
                strncat(out_txt, table->items[i].sym, out_sz - strlen(out_txt) - 1);
                clen = 0;
                cur[0] = '\0';
                break;
            }
        }
    }
}

//Tree from Codes
TreeNode *build_tree_from_codes(const CodeTable *table) {
    TreeNode *root = new_node(NULL, 0);
    for (int i = 0; i < table->count; i++) {
        TreeNode *cur = root;
        const char *c = table->items[i].code;
        for (; *c; c++) {
            if (*c == '0') {
                if (!cur->left) cur->left = new_node(NULL, 0);
                cur = cur->left;
            } else {
                if (!cur->right) cur->right = new_node(NULL, 0);
                cur = cur->right;
            }
        }
        strncpy(cur->sym, table->items[i].sym, SYM_LEN - 1);
        cur->is_leaf = 1;
    }
    return root;
}

//Metrics
double get_entropy(const CodeTable *table, int total_len) {
    if (total_len <= 0) return 0.0;
    double h = 0.0;
    for (int i = 0; i < table->count; i++) {
        double p = (double)table->items[i].count / total_len;
        if (p > 0.0) h -= p * log2(p);
    }
    return h;
}

double get_average_length(const CodeTable *table, int total_len) {
    if (total_len <= 0) return 0.0;
    double l = 0.0;
    for (int i = 0; i < table->count; i++) {
        double p = (double)table->items[i].count / total_len;
        l += p * strlen(table->items[i].code);
    }
    return l;
}

double get_kraft_sum(const CodeTable *table) {
    double sum = 0.0;
    for (int i = 0; i < table->count; i++) {
        size_t len = strlen(table->items[i].code);
        if (len > 0) sum += pow(2.0, -(double)len);
    }
    return sum;
}

//Prefix-Free & Ambiguity Inspection
int check_prefix_free(const CodeTable *table, char *detail, size_t sz) {
    for (int i = 0; i < table->count; i++) {
        size_t li = strlen(table->items[i].code);
        for (int j = 0; j < table->count; j++) {
            if (i == j) continue;
            size_t lj = strlen(table->items[j].code);
            if (lj >= li && strncmp(table->items[j].code, table->items[i].code, li) == 0) {
                if (detail && sz) {
                    snprintf(detail, sz, "'%s' (%s) is a prefix of '%s' (%s)",
                             table->items[i].sym, table->items[i].code,
                             table->items[j].sym, table->items[j].code);
                }
                return 0; // Not prefix free
            }
        }
    }
    if (detail && sz) snprintf(detail, sz, "Valid Prefix-Free code: No codeword is a prefix of any other.");
    return 1;
}

int check_ambiguity(const CodeTable *table, char *detail, size_t sz) {
    double k = get_kraft_sum(table);
    if (k > 1.000001) {
        if (detail && sz) snprintf(detail, sz, "Ambiguous: Kraft sum %.4f > 1.0 (violates Kraft-McMillan inequality)", k);
        return 1;
    }
    if (check_prefix_free(table, NULL, 0)) {
        if (detail && sz) snprintf(detail, sz, "Unambiguous: Code is prefix-free (instantaneously decodable)");
        return 0;
    }

    // Sardinas-Patterson test 
    char s_prev[128][CODE_LEN];
    int n_prev = 0;
    for (int i = 0; i < table->count; i++) {
        size_t li = strlen(table->items[i].code);
        for (int j = 0; j < table->count; j++) {
            if (i == j) continue;
            size_t lj = strlen(table->items[j].code);
            if (lj > li && strncmp(table->items[j].code, table->items[i].code, li) == 0 && n_prev < 128) {
                strncpy(s_prev[n_prev++], table->items[j].code + li, CODE_LEN - 1);
            }
        }
    }

    for (int i = 0; i < n_prev; i++) {
        for (int j = 0; j < table->count; j++) {
            if (strcmp(table->items[j].code, s_prev[i]) == 0) {
                if (detail && sz) snprintf(detail, sz, "Ambiguous: Dangling suffix '%s' in S1 is an original codeword", s_prev[i]);
                return 1;
            }
        }
    }

    if (detail && sz) snprintf(detail, sz, "Unambiguous: Verified unique decodability (Sardinas-Patterson)");
    return 0;
}

int parse_custom_codes(const char *input, CodeTable *table, char *err, size_t sz) {
    const char *p = input;
    table->count = 0;

    while (*p) {
        while (*p && (isspace((unsigned char)*p) || *p == ',' || *p == ';')) p++;
        if (!*p) break;

        char sym[SYM_LEN] = {0}, code[CODE_LEN] = {0};
        int si = 0, ci = 0;

        while (*p && !isspace((unsigned char)*p) && *p != '-' && *p != ':' && *p != '=' && *p != ',' && *p != ';') {
            if (si < SYM_LEN - 1) sym[si++] = *p;
            p++;
        }
        if (si == 0) { if (err) snprintf(err, sz, "Expected symbol name near '%s'", p); return 0; }

        while (*p && (isspace((unsigned char)*p) || *p == '-' || *p == ':' || *p == '=')) p++;

        while (*p == '0' || *p == '1') {
            if (ci < CODE_LEN - 1) code[ci++] = *p;
            p++;
        }
        if (ci == 0) { if (err) snprintf(err, sz, "Symbol '%s' must have binary code ('0' or '1')", sym); return 0; }

        if (table->count < MAX_SYMS) {
            strncpy(table->items[table->count].sym, sym, SYM_LEN - 1);
            table->items[table->count].count = 1;
            strncpy(table->items[table->count].code, code, CODE_LEN - 1);
            table->count++;
        }
    }
    if (table->count == 0) { if (err) snprintf(err, sz, "No valid pairs found (e.g. A-10, B-00)"); return 0; }
    return 1;
}
