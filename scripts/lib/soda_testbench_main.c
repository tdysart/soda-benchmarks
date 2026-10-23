/* Test driver for the cpu and esp backends.
 *
 * Everything that varies per kernel lives in the generated testdata.h that
 * torchscript.py --emit-testdata writes: the parameter arrays, their order and
 * count (as the TD_CALL macro, since C cannot spell a variable arity), the
 * output buffers (one per result: a kernel may return several tensors) and the
 * golden results PyTorch produced for the same inputs. TD_OUTPUTS(X) expands
 * X(buffer, golden, count) once per result, which is how this file walks them.
 * This file therefore never changes with the kernel.
 *
 * Exit status is always 0. The Makefile rule captures stdout as the artifact,
 * and one of the two supported cpu configurations -- the ESP-lowered kernel
 * against the mock runtime, which never writes the output -- is expected to
 * report a mismatch. `make check` is what turns TEST FAILED into an error.
 */

#include <stdio.h>

#include "testdata.h"

/* Lowered with the bare-pointer memref convention, so every operand -- rank-0
 * scalars included -- arrives as exactly one pointer. TD_DECL spells the
 * prototype because only the generated header knows the arity. */
extern TD_DECL(forward_kernel);

/* Compare one result with its golden; returns the number of elements beyond
 * the tolerance and raises *max_err. */
static unsigned check_result(int k, const td_elem_t *out,
                             const td_elem_t *golden, unsigned n,
                             td_elem_t *max_err)
{
    unsigned i, errors = 0;
    for (i = 0; i < n; i++) {
        td_elem_t err = out[i] - golden[i];
        if (err < 0) err = -err;
        if (err > *max_err) *max_err = err;
        if (err > (td_elem_t)TD_TOL) {
            if (errors < 10)
                printf("  MISMATCH in result %d at [%u]: got=%g want=%g err=%g\n",
                       k, i, (double)out[i], (double)golden[i], (double)err);
            errors++;
        }
    }
    return errors;
}

#define TD_COUNT(out, golden, n) + (unsigned)(n)
#define TD_CHECK(out, golden, n) \
    errors += check_result(k++, out, golden, (unsigned)(n), &max_err);

int main(void)
{
    int       k       = 0;
    unsigned  errors  = 0;
    unsigned  total   = 0 TD_OUTPUTS(TD_COUNT);
    td_elem_t max_err = 0;

    printf("kernel=%s dataset=%s dtype=%s results=%d elements=%u tol=%g\n",
           TD_KERNEL, TD_DATASET, TD_DTYPE, (int)TD_NOUT, total,
           (double)TD_TOL);

    TD_CALL(forward_kernel);

    TD_OUTPUTS(TD_CHECK)

    printf("---------------------------------\n");
    if (errors == 0)
        printf("TEST PASSED (max error: %g)\n", (double)max_err);
    else
        printf("TEST FAILED (%u/%u elements exceed tolerance %g)\n", errors,
               total, (double)TD_TOL);
    printf("---------------------------------\n");

    return 0;
}
