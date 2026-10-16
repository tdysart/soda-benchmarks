#include <stdio.h>
#include <string.h>
#include <mdpi/mdpi_user.h>

#define M 8
#define K 16
#define L 10
#define P 6
#define N 12

/* Reference model of forward_kernel: D = ((A * B) * C) * E, single precision. The IR from soda-opt
   has no C source to run natively, so this definition is what the hardware result is compared
   with. The parameters are void* to match how soda-opt's testbench declares the kernel. */
void forward_kernel(void *a, void *b, void *c, void *e, void *d)
{
  const float *A = a, *B = b, *C = c, *E = e;
  float *D = d;
  float AB[M][L], ABC[M][P];
  for (int i = 0; i < M; i++)
    for (int j = 0; j < L; j++) {
      float acc = 0.0f;
      for (int k = 0; k < K; k++) acc += A[i * K + k] * B[k * L + j];
      AB[i][j] = acc;
    }
  for (int i = 0; i < M; i++)
    for (int j = 0; j < P; j++) {
      float acc = 0.0f;
      for (int k = 0; k < L; k++) acc += AB[i][k] * C[k * P + j];
      ABC[i][j] = acc;
    }
  for (int i = 0; i < M; i++)
    for (int j = 0; j < N; j++) {
      float acc = 0.0f;
      for (int k = 0; k < P; k++) acc += ABC[i][k] * E[k * N + j];
      D[i * N + j] = acc;
    }
}

int main(void)
{
  static float A[M * K], B[K * L], C[L * P], E[P * N], D[M * N];
  for (int i = 0; i < M * K; i++) A[i] = ((i * 7) % 9 - 4) * 0.25f;
  for (int i = 0; i < K * L; i++) B[i] = ((i * 5) % 7 - 3) * 0.25f;
  for (int i = 0; i < L * P; i++) C[i] = ((i * 3) % 5 - 2) * 0.5f;
  for (int i = 0; i < P * N; i++) E[i] = ((i * 11) % 6 - 2) * 0.25f;
  for (int i = 0; i < M * N; i++) D[i] = -1.0f;
  m_param_alloc(0, sizeof(A));
  m_param_alloc(1, sizeof(B));
  m_param_alloc(2, sizeof(C));
  m_param_alloc(3, sizeof(E));
  m_param_alloc(4, sizeof(D));
  forward_kernel(A, B, C, E, D);
  printf("D[0]=%f D[%d]=%f\n", D[0], M * N - 1, D[M * N - 1]);
  return 0;
}
