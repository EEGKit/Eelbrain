'''
Created on Jul 22, 2013

@author: christian
'''
from eelbrain import datasets, plot, testnd
from eelbrain._utils.testing import requires_mne_sample_data


def test_plot_topomap():
    "Test plot.Topomap"
    ds = datasets.get_uts(utsnd=True)
    topo = ds.eval('utsnd.summary(time=(0.075, 0.125))')

    p = plot.Topomap(topo, ds=ds, show=False)
    p.add_contour('V', 1, '#00FF00')
    p.close()
    p = plot.Topomap(topo, ds=ds, vmax=0.2, w=2, show=False)
    p.close()
    p = plot.Topomap(topo, 'A%B', ds=ds, axw=2, show=False)
    p.close()
    p = plot.Topomap(topo, ds=ds, sensorlabels=None, show=False)
    p.close()


@requires_mne_sample_data
def test_plot_topomap_mne():
    "Test plot.Topomap with MNE data"
    ds = datasets.get_mne_sample(sub=[0, 1], sns=True)
    p = plot.Topomap(ds['meg'].summary(time=(.1, .12)), proj='left', show=False)
    p.close()


def test_plot_butterfly():
    "Test plot.TopoButterfly"
    ds = datasets.get_uts(utsnd=True)
    p = plot.TopoButterfly('utsnd', ds=ds, show=False)
    p.set_topo_t(0.2)
    p.close()
    p = plot.TopoButterfly('utsnd', ds=ds, vmax=0.2, w=2, show=False)
    p.close()
    p = plot.TopoButterfly('utsnd', 'A%B', ds=ds, axw=2, show=False)
    p.close()
    p = plot.TopoButterfly('utsnd', mark=[1, 2], ds=ds, show=False)
    p.close()
    p = plot.TopoButterfly('utsnd', mark=['1', '2'], ds=ds, show=False)
    p.close()


def test_plot_array():
    "Test plot.TopoArray"
    ds = datasets.get_uts(utsnd=True)
    p = plot.TopoArray('utsnd', ds=ds, show=False)
    p.set_topo_t(0, 0.2)
    p.close()
    p = plot.TopoArray('utsnd', ds=ds, vmax=0.2, w=2, show=False)
    p.close()
    p = plot.TopoArray('utsnd', 'A%B', ds=ds, axw=4, show=False)
    p.close()

    # results
    res = testnd.ttest_ind('utsnd', 'A', ds=ds, pmin=0.05, tstart=0.1,
                           tstop=0.3, samples=2)
    p = plot.TopoArray(res, show=False)
    p.set_topo_t(0, 0.)
    p.close()
