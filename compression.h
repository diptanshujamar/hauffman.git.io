#ifndef COMPRESSION_H
#define COMPRESSION_H

#include <stddef.h>

#define MAX_SYMS 256
#define SYM_LEN  8
#define CODE_LEN 64

typedef struct {
    char sym[SYM_LEN];
    int  count;
    char code[CODE_LEN];
} CodeEntry;

typedef struct {
    CodeEntry items[MAX_SYMS];
    int count;
} CodeTable;

typedef struct TreeNode {
    char sym[SYM_LEN];
    int  is_leaf;
    int  freq;
    struct TreeNode *left;
    struct TreeNode *right;
} TreeNode;

//Core Compression 
int  get_frequencies(const char *text, CodeTable *table);
void huffman_encode(const char *text, CodeTable *table, char *out_bin, size_t out_sz);
void shannon_fano_encode(const char *text, CodeTable *table, char *out_bin, size_t out_sz);
void decode_bitstream(const char *binary, const CodeTable *table, char *out_txt, size_t out_sz);

//Tree Operations 
TreeNode *build_tree_from_codes(const CodeTable *table);
int       get_tree_depth(const TreeNode *root);
void      free_tree(TreeNode *root);

// Discrete Math Metrics 
double get_entropy(const CodeTable *table, int total_len);
double get_average_length(const CodeTable *table, int total_len);
double get_kraft_sum(const CodeTable *table);

// Prefix-Free & Ambiguity Inspection
int check_prefix_free(const CodeTable *table, char *detail, size_t sz);
int check_ambiguity(const CodeTable *table, char *detail, size_t sz);
int parse_custom_codes(const char *input, CodeTable *table, char *err, size_t sz);

#endif
