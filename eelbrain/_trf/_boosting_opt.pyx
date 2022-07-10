# Author: Christian Brodbeck <christianbrodbeck@nyu.edu>
# cython: language_level=3, boundscheck=False, wraparound=False
from libc.math cimport fabs
from cpython.mem cimport PyMem_Malloc, PyMem_Free
from cython.parallel import prange
import numpy as np

cimport numpy as np

ctypedef np.int8_t INT8
ctypedef np.int64_t INT64
ctypedef np.float64_t FLOAT64


def l1(
        FLOAT64 [:] x,
        INT64 [:,:] indexes,
    ):
    cdef:
        double out = 0.
        Py_ssize_t i, seg_i

    with nogil:
        for seg_i in range(indexes.shape[0]):
            for i in range(indexes[seg_i, 0], indexes[seg_i, 1]):
                out += fabs(x[i])

    return out


def l2(
        FLOAT64 [:] x,
        INT64 [:,:] indexes,
    ):
    cdef:
        double out = 0.
        Py_ssize_t i, seg_i

    with nogil:
        for seg_i in range(indexes.shape[0]):
            for i in range(indexes[seg_i, 0], indexes[seg_i, 1]):
                out += x[i] ** 2

    return out


cdef void l1_for_delta(
        FLOAT64 [:] y_error,
        FLOAT64 [:] x,
        double x_pad,  # pad x outside valid convolution area
        INT64 [:,:] indexes,  # training segment indexes
        double delta,
        int shift,  # TRF element offset
        double* e_add,
        double* e_sub,
    ) nogil:
    cdef:
        double d
        Py_ssize_t i, seg_i, seg_start, seg_stop, conv_start, conv_stop

    e_add[0] = 0.
    e_sub[0] = 0.

    for seg_i in range(indexes.shape[0]):
        seg_start = indexes[seg_i, 0]
        seg_stop = indexes[seg_i, 1]
        # determine valid convolution segment
        conv_start = seg_start
        conv_stop = seg_stop
        if shift > 0:
            conv_start += shift
        elif shift < 0:
            conv_stop += shift
        # padding
        d = delta * x_pad
        # pre-
        for i in range(seg_start, conv_start):
            e_add[0] += fabs(y_error[i] - d)
            e_sub[0] += fabs(y_error[i] + d)
        # post-
        for i in range(conv_stop, seg_stop):
            e_add[0] += fabs(y_error[i] - d)
            e_sub[0] += fabs(y_error[i] + d)
        # valid segment
        for i in range(conv_start, conv_stop):
            d = delta * x[i - shift]
            e_add[0] += fabs(y_error[i] - d)
            e_sub[0] += fabs(y_error[i] + d)


cdef void l2_for_delta(
        FLOAT64 [:] y_error,
        FLOAT64 [:] x,
        double x_pad,  # pad x outside valid convolution area
        INT64 [:,:] indexes,  # training segment indexes
        double delta,
        int shift,
        double* e_add,
        double* e_sub,
    ) nogil:
    cdef:
        double d
        size_t i, seg_i, seg_start, seg_stop, conv_start, conv_stop

    e_add[0] = 0.
    e_sub[0] = 0.

    for seg_i in range(indexes.shape[0]):
        seg_start = indexes[seg_i, 0]
        seg_stop = indexes[seg_i, 1]
        # determine valid convolution segment
        conv_start = seg_start
        conv_stop = seg_stop
        if shift > 0:
            conv_start += shift
        elif shift < 0:
            conv_stop += shift
        # padding
        d = delta * x_pad
        # pre-
        for i in range(seg_start, conv_start):
            e_add[0] += (y_error[i] - d) ** 2
            e_sub[0] += (y_error[i] + d) ** 2
        # post-
        for i in range(conv_stop, seg_stop):
            e_add[0] += (y_error[i] - d) ** 2
            e_sub[0] += (y_error[i] + d) ** 2
        # part of the segment that is affected
        for i in range(conv_start, conv_stop):
            d = delta * x[i - shift]
            e_add[0] += (y_error[i] - d) ** 2
            e_sub[0] += (y_error[i] + d) ** 2


cpdef double error_for_indexes(
        FLOAT64[:] x,
        INT64[:,:] indexes,  # (n_segments, 2)
        int error,  # 1 --> l1; 2 --> l2
):
    cdef:
        Py_ssize_t seg_i, i
        double out = 0

    if error == 1:
        for seg_i in range(indexes.shape[0]):
            for i in range(indexes[seg_i, 0], indexes[seg_i, 1]):
                out += fabs(x[i])
    else:
        for seg_i in range(indexes.shape[0]):
            for i in range(indexes[seg_i, 0], indexes[seg_i, 1]):
                out += x[i] ** 2
    return out


def boosting_runs(
        FLOAT64[:,:] y,  # (n_y, n_times)
        FLOAT64[:,:] x,  # (n_stims, n_times)
        FLOAT64 [:] x_pads,  # (n_stims,)
        tuple split_train,
        tuple split_validate,
        tuple split_train_and_validate,
        INT64 [:] i_start_by_x,  # (n_stims,) kernel start index
        INT64 [:] i_stop_by_x, # (n_stims,) kernel stop index
        double delta,
        double mindelta,
        int error,
        int selective_stopping,
):
    """Estimate multiple filters with boosting"""
    cdef:
        Py_ssize_t n_y = len(y)
        Py_ssize_t n_x = len(x)
        Py_ssize_t n_splits = len(split_train)
        long n_total = n_splits * n_y
        Py_ssize_t n_times_h = np.max(i_stop_by_x) - np.min(i_start_by_x)
        FLOAT64[:,:,:,:] hs = np.empty((n_splits, n_y, n_x, n_times_h))
        INT8[:,:] hs_failed = np.zeros((n_splits, n_y), 'int8')
        long i_y, i_split
        FLOAT64[:,:] h
        Py_ssize_t i

    for i in prange(n_total, nogil=True):
        i_y = i // n_splits
        i_split = i % n_splits
        with gil:
            # print('starting', i, 'of', n_total)
            hs_failed[i_split, i_y] = boosting_run(y[i_y], x, x_pads, hs[i_split, i_y], split_train[i_split], split_validate[i_split], split_train_and_validate[i_split], i_start_by_x, i_stop_by_x, delta, mindelta, error, selective_stopping)
    # print('done')
    return hs.base, np.asarray(hs_failed, 'bool')


cdef struct BoostingStep:
    long i_step
    long i_stim
    long i_time
    double delta
    double e_test
    double e_train
    BoostingStep* previous


cdef int boosting_run(
        FLOAT64 [:] y,  # (n_times,)
        FLOAT64 [:,:] x,  # (n_stims, n_times)
        FLOAT64 [:] x_pads,  # (n_stims,)
        FLOAT64 [:,:] h,
        INT64[:,:] split_train,
        INT64[:,:] split_validate,
        INT64[:,:] split_train_and_validate,
        INT64 [:] i_start_by_x,  # (n_stims,) kernel start index
        INT64 [:] i_stop_by_x, # (n_stims,) kernel stop index
        double delta,
        double mindelta,
        int error,
        int selective_stopping,
):
    """Estimate one filter with boosting

    Parameters
    ----------
    y : array (n_times,)
        Dependent signal, time series to predict.
    x : array (n_stims, n_times)
        Stimulus.
    x_pads : array (n_stims,)
        Padding for x.
    split_train
        Training data index.
    split_validate
        Validation data index.
    split_train_and_validate
        Training and validation data index.
    i_start_by_x : ndarray
        Array of i_start for trfs.
    i_stop_by_x : ndarray
        Array of i_stop for TRF.
    delta : scalar
        Step of the adjustment.
    mindelta : scalar
        Smallest delta to use. If no improvement can be found in an iteration,
        the first step is to divide delta in half, but stop if delta becomes
        smaller than ``mindelta``.
    error : str
        Error function to use.
    selective_stopping : int
        Selective stopping.
    """
    cdef:
        int out
        Py_ssize_t n_x = len(x)
        Py_ssize_t n_times = x.shape[1]
        Py_ssize_t n_times_h = h.shape[1]
        long i_start = np.min(i_start_by_x)
        long n_times_trf = np.max(i_stop_by_x) - i_start
        BoostingStep *step
        BoostingStep *step_i
        BoostingStep *history = NULL

    # buffers
    cdef:
        FLOAT64[:] y_error = y
        FLOAT64[:,:] new_error = np.empty((n_x, n_times_h))
        INT8[:,:] new_sign = np.empty((n_x, n_times_h), np.int8)
        INT8[:] x_active = np.ones(n_x, np.int8)
    h[...] = 0
    new_error[...] = np.inf  # ignore values outside TRF

    # history
    cdef:
        long i_stim = -1
        long i_time = -1
        double delta_signed = 0.
        double best_test_error = np.inf
        size_t best_iteration = 0
        int n_bad, undo
        long argmin

    # pre-assign iterators
    for i_step in range(999999):
        # evaluate current h
        e_train = error_for_indexes(y_error, split_train, error)
        e_test = error_for_indexes(y_error, split_validate, error)
        step = <BoostingStep*> PyMem_Malloc(sizeof(BoostingStep))
        step[0] = BoostingStep(i_step, i_stim, i_time, delta_signed, e_test, e_train, history)
        history = step

        # print(i_step, 'error:', e_test)

        # evaluate stopping conditions
        if e_test < best_test_error:
            # print(' ', e_test, '<', best_test_error)
            best_test_error = e_test
            best_iteration = i_step
        elif i_step >= 2:
            step_i = step.previous
            # print(' ', e_test, '>', step_i.e_test, '? (', step.i_step, step_i.i_step, ')')
            if e_test > step_i.e_test:
                if selective_stopping:
                    if selective_stopping > 1:
                        n_bad = selective_stopping - 1
                        # only stop if the predictor overfits twice without intermittent improvement
                        undo = 0
                        while step_i.previous != NULL:
                            if step_i.e_test > e_test:
                                break  # the error improved
                            elif step_i.i_stim == i_stim:
                                if step_i.e_test > step_i.previous[0].e_test:
                                    # the same stimulus caused an error increase
                                    if n_bad == 1:
                                        undo = i
                                        break
                                    n_bad -= 1
                                else:
                                    break
                            step_i = step_i.previous
                    else:
                        undo = -1

                    if undo:
                        # print(' undo')
                        # revert changes
                        for i in range(-undo):
                            h[step.i_stim, step.i_time] -= step.delta
                            update_error(y_error, x[step.i_stim], x_pads[step.i_stim], split_train_and_validate, -step.delta, step.i_time + i_start)
                            step_i = step.previous
                            PyMem_Free(step)
                            step = step_i
                        history = step
                        # disable predictor
                        x_active[i_stim] = False
                        if not np.any(x_active):
                            break
                        new_error[i_stim, :] = np.inf
                # Basic
                # -----
                # stop the iteration if all the following requirements are met
                # 1. more than 10 iterations are done
                # 2. The testing error in the latest iteration is higher than that in
                #    the previous two iterations
                elif i_step > 10 and e_test > step_i.previous[0].e_test:
                    # print("error(test) not improving in 2 steps")
                    break

        # generate possible movements -> training error
        generate_options(y_error, x, x_pads, x_active, split_train, i_start, i_start_by_x, i_stop_by_x, error, delta, new_error, new_sign)
        # i_stim, i_time = np.unravel_index(np.argmin(new_error), h.shape)  # (not supported by numba)
        argmin = np.argmin(new_error)
        i_stim = argmin // n_times_trf
        i_time = argmin % n_times_trf
        new_train_error = new_error[i_stim, i_time]
        delta_signed = new_sign[i_stim, i_time] * delta
        # print(new_train_error, end=', ')

        # If no improvements can be found reduce delta
        if new_train_error > step.e_train:
            delta *= 0.5
            if delta >= mindelta:
                i_stim = i_time = -1
                delta_signed = 0.
                # print("new delta: %s" % delta)
                continue
            else:
                # print("No improvement possible for training data")
                break

        # abort if we're moving in circles
        if step.delta and i_stim == step.i_stim and i_time == step.i_time and delta_signed == -step.delta:
            # print("Moving in circles")
            break

        # update h with best movement
        h[i_stim, i_time] += delta_signed
        update_error(y_error, x[i_stim], x_pads[i_stim], split_train_and_validate, delta_signed, i_time + i_start)
    else:
        raise RuntimeError("Boosting: maximum number of iterations exceeded")

    # reverse changes after best iteration
    if best_iteration:
        while step.i_step > best_iteration:
            if step.delta:
                h[step.i_stim, step.i_time] -= step.delta
            step = step.previous
        out = 0
    else:
        out = 1

    # Free history memory
    step = history
    while step.previous != NULL:
        step_i = step.previous
        PyMem_Free(step)
        step = step_i
    return out


cdef void generate_options(
        FLOAT64 [:] y_error,
        FLOAT64 [:,:] x,  # (n_stims, n_times)
        FLOAT64 [:] x_pads,  # (n_stims,)
        INT8 [:] x_active,  # for each predictor whether it is still used
        INT64 [:,:] indexes,  # training segment indexes
        int i_start,  # kernel start index (time axis offset)
        INT64 [:] i_start_by_x,  # (n_stims,) kernel start index
        INT64 [:] i_stop_by_x, # (n_stims,) kernel stop index
        int error,  # ID of the error function (l1/l2)
        double delta,
        # buffers
        FLOAT64 [:,:] new_error,  # (n_stims, n_times_trf)
        INT8 [:,:] new_sign,  # (n_stims, n_times_trf)
    ) nogil:
    cdef:
        double e_add, e_sub, x_pad
        size_t n_stims = new_error.shape[0]
        Py_ssize_t i_stim, i_time
        FLOAT64 [:] x_stim

    for i_stim in range(n_stims):
        if x_active[i_stim] == 0:
            continue
        x_stim = x[i_stim]
        x_pad = x_pads[i_stim]
        for i_time in range(i_start_by_x[i_stim], i_stop_by_x[i_stim]):
            # +/- delta
            if error == 1:
                l1_for_delta(y_error, x_stim, x_pad, indexes, delta, i_time, &e_add, &e_sub)
            else:
                l2_for_delta(y_error, x_stim, x_pad, indexes, delta, i_time, &e_add, &e_sub)

            i_time -= i_start
            if e_add > e_sub:
                new_error[i_stim, i_time] = e_sub
                new_sign[i_stim, i_time] = -1
            else:
                new_error[i_stim, i_time] = e_add
                new_sign[i_stim, i_time] = 1


cdef void update_error(
        FLOAT64 [:] y_error,
        FLOAT64 [:] x,
        double x_pad,  # pad x outside valid convolution area
        INT64 [:,:] indexes,  # segment indexes
        double delta,
        int shift,
    ) nogil:
    cdef:
        Py_ssize_t i, seg_i, seg_start, seg_stop, conv_start, conv_stop

    for seg_i in range(indexes.shape[0]):
        seg_start = indexes[seg_i, 0]
        seg_stop = indexes[seg_i, 1]
        conv_start = seg_start
        conv_stop = seg_stop
        if shift > 0:
            conv_start += shift
        elif shift < 0:
            conv_stop += shift
        # padding
        d = delta * x_pad
        # pre-
        for i in range(seg_start, conv_start):
            y_error[i] -= d
        # post-
        for i in range(conv_stop, seg_stop):
            y_error[i] -= d
        # part of the segment that is affected
        for i in range(conv_start, conv_stop):
            y_error[i] -= delta * x[i - shift]
