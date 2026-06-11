# NOTES:

* add 8-14um with discretized steps on material file provided (DO THIS CHRIS DO NOT IGNORE)
* 'metasurfaceAPP/writematlib'- edit where filepaths save to
* ignore the taper stuff

# 

# LWIR Metasurface Library Quick Start

This folder is a self-contained handoff copy for generating RCWA libraries for
8-14 um metasurfaces.

## Folder Contents

* `20260520\_MetasurfaceApp/`
Main metasurface app and library-generation pipeline.
* `RCWA functions/`
RETICOLO/RCWA dependency files required by the solver.
* `Fourier Functions/`
Fourier optics helper functions. These are not required for a basic library
sweep, but are included for downstream propagation work.
* Root-level `Generate\_\*` and `GetFilterTable\_\*` scripts
Older one-off scripts. For new work, use the app pipeline unless there is a
specific reason to reproduce an old workflow.

## Required Material File

Create a silicon material Excel file for the LWIR range and place it here:

```text
For Tian/Material Dielectric Function/Si\_LWIR\_8to14.xlsx
```

The file must have these columns:

```text
wl    n    k
```

Use wavelength units of micrometers. For example, `wl = 8.0 ... 14.0`.
The pipeline will stop with a clear error if the requested wavelength window is
outside the material file range.

## Main Script

Open MATLAB and run:

```matlab
cd('D:\\Rahul\\Metasurface\\For Tian\\20260520\_MetasurfaceApp')
RunLibraryPipeline
```

If the folder is copied elsewhere, use the copied path. The script now adds the
local `RCWA functions` folder automatically from the handoff directory.

## Edit These Settings First

In `20260520\_MetasurfaceApp/RunLibraryPipeline.m`, edit the user-parameter
section near the top.

Common settings:

```matlab
shape\_name = 'circle\_with\_cap';

min\_p1 = 0.2;
max\_p1\_fraction = 0.8;
num\_p1 = 20;

min\_p2 = 0.20;
max\_p2 = 0.60;
num\_p2 = 9;

heights = 1.3;
h\_cap   = 0.030;
pitches = 1.0:0.025:1.20;

requested\_min\_wavelength = 8.00;
requested\_max\_wavelength = 14.00;

angles = \[0, 10, 20];
nn     = \[12, 12];
```

For a circle or square, only `p1` is used. For a cross or ellipse, `p1` and
`p2` are both used.

Available shapes:

```matlab
shape\_registry()
```

Current options include:

```text
circle\_with\_cap
tapered\_circle\_with\_cap
square\_with\_cap
cross\_with\_cap
tapered\_cross\_with\_cap
ellipse\_with\_cap
```

## Tapered Shapes

For `tapered\_cross\_with\_cap` and `tapered\_circle\_with\_cap`, these settings are
used:

```matlab
taper\_mid\_delta    = -0.04;
taper\_bottom\_delta = -0.113;
taper\_num\_slices   = 30;
```

The swept `p1` value is the top width or top diameter. Negative deltas mean the
middle or bottom is narrower than the top.

## Output

Results are written under:

```text
For Tian/Library Data2/<pillar>\_on\_<substrate>\_<shape>/<timestamp>/
```

Inside each run:

```text
TE/
TM/
Averaged/
```

The most useful final files are in `Averaged/`:

```text
TransmissionTable\_<shape>\_theta0.csv
TransmissionTable\_<shape>\_theta10.csv
TransmissionTable\_<shape>\_theta20.csv
```

These are TE/TM-averaged filter tables.

## Resume an Overnight Run

The script checkpoints by skipping existing `.mat` files. To resume a run after
MATLAB closes, set:

```matlab
resume\_run\_id = '2026-05-19\_131245';
```

Use the timestamp folder name from the run you want to continue. Leave it empty
to start a new run:

```matlab
resume\_run\_id = '';
```

## Viewing Results

Open the GUI:

```matlab
cd('D:\\Rahul\\Metasurface\\For Tian\\20260520\_MetasurfaceApp')
MetasurfaceExplorer
```

Use the library viewer to select the run folder, not the `TE` or `TM` subfolder.
For example, select:

```text
For Tian/Library Data2/Si\_on\_SiO2\_circle\_with\_cap/2026-06-04\_120000
```

The viewer can show TE, TM, and averaged spectra where available.

## LWIR Checks Before Large Runs

1. Confirm the material file covers the entire wavelength range.
2. Check grating orders for the largest pitch:

```matlab
wavelength = linspace(8, 14, 200);
check\_grating\_orders(max(pitches), wavelength, n\_substrate, n\_background, max(angles));
```

3. Run a tiny test first:

```matlab
pitches = 4.0;
num\_p1 = 2;
num\_p2 = 1;
angles = 0;
nn = \[6, 6];
```

4. Increase `nn` and compare results for a few geometries to check convergence.
5. Only then start the full overnight sweep.

## Common Issues

* `Material file not found`
Create the `Material Dielectric Function` folder and put
`Si\_LWIR\_8to14.xlsx` inside it, or edit `material\_file`.
* `Requested wavelength range ... outside the material file range`
The `wl` column does not span 8-14 um, or the units are not micrometers.
* No output appears in `Averaged`
Check that both TE and TM finished. Averaging needs matching TE/TM files.
* Very slow run
Reduce `nn`, `num\_p1`, `num\_p2`, number of pitches, or number of wavelengths
for testing. Use higher `nn` only after convergence checks.

