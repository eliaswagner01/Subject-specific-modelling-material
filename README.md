# Subject-Specific Femur Model Modification Material

This folder contains the custom scripts and support files used to create a subject-specific femur modification of the baseline OpenSim model from (Uhlrich et al., 2022). The workflow combines functionality from STAPLE (Modenese and Renault, 2021), NMSBuilder (Valente et al., 2017), and OpenSim (Seth et al., 2018) and uses ressources from the Step-by-step modelling guide (Modenese et al., 2018). 

The overall model modification process is illustrated here:

<img src="images/modelModificationProcess.png" alt="Model modification process" width="700">

## Required Software

To run the scripts, users need:

- MATLAB, tested with the OpenSim MATLAB API available.
- OpenSim 4.x with the MATLAB scripting interface configured.
- The STAPLE toolbox on the MATLAB path. STAPLE is available here: [Simtk STAPLE](https://simtk.org/projects/msk-staple)
- NMSBuilder. NMSBuilder is available here: [Simtk NMSBuilder](https://simtk.org/frs/?group_id=978)

STAPLE itself requires MATLAB toolboxes used by its morphology algorithms:

- Curve Fitting Toolbox
- Statistics and Machine Learning Toolbox

The MATLAB OpenSim API must work before running the scripts. A quick test in MATLAB is:

```matlab
import org.opensim.modeling.*
model = Model('OpenSim/LaiUhlrich2022.osim');
```

## External Method Dependencies

The custom workflow builds on:

- STAPLE: Shared Tools for Automatic Personalised Lower Extremity modelling.
- Step-by-step subject-specific workflow described by Modenese et al. (2018).
- OpenSim ScaleTool and MATLAB API.
- NMSBuilder for registering muscle landmark clouds

## Expected Input Data

The workflow assumes that subject-specific femur geometries are available in a STAPLE-compatible structure, for example:

```text
bone_datasets/
  VISIBLE_H/
    tri/
      femur_r.mat
      femur_l.mat
```

The femur geometry coordinates are assumed to be in millimetres. OpenSim model coordinates are in metres, so the model modification script uses:

```matlab
mm_to_m = 0.001;
```

The OpenSim model is assumed to use names according to Uhlrich et al. (2022), including:

```text
Bodies:
  femur_r
  femur_l

Joints:
  hip_r, hip_l
  walker_knee_r, walker_knee_l
  patellofemoral_r, patellofemoral_l

Marker set:
  LaiUhlrich2022_markers_augmenter.xml
```

## Workflow Overview

### 1. Create femur coordinate systems and femur scale factors

Run:

```matlab
MATLAB functions/createFemurModel.m
```

This script:

- adds `STAPLE` to the MATLAB path,
- loads subject-specific femur triangulations,
- processes right and left femur geometries,
- computes STAPLE joint coordinate systems,
- saves femur coordinate-system data,
- computes right and left uniform femur scale factors,
- scales the generic LaiUhlrich2022 model femurs using OpenSim ScaleTool.

Important outputs include:

```text
opensim_models_JBiomech/
  automatic_VISIBLE_H_R.osim
  automatic_VISIBLE_H_L.osim
  automatic_VISIBLE_H_R_Geometries/
  automatic_VISIBLE_H_L_Geometries/
  fitted_geometries/VISIBLE_H/
    STAPLE_femur_coordinate_systems_r.mat
    STAPLE_femur_coordinate_systems_l.mat
    Femur_uniform_scaling_factor_r.txt
    Femur_uniform_scaling_factor_l.txt
```

### 2. Extract model landmarks for NMSBuilder

Run:

```matlab
MATLAB functions/extractFemurPathPoints.m
```

This script extracts:

- femur muscle path points,
- femur wrap-object origins,

It writes landmark cloud for the right and left femur:

```text
NMSBuilderRajagopal_LaiUhlrich2022_femur_r_landmarks_and_muscle_path_points.txt
NMSBuilderRajagopal_LaiUhlrich2022_femur_l_landmarks_and_muscle_path_points.txt
```

These files can be imported into NMSBuilder as landmark clouds together with the femur geometries.

### 3. Register landmarks in NMSBuilder and snap muscle path points

Use NMSBuilder to register muscle path points and wrap object origins onto the subject-specific femur geometry and Run:

```matlab
MATLAB functions/snapLandmarks.m
```
This script snaps registered muscle path points to the bone surface.

The expected snapped outputs are:

```text
NMSBuilder/Muscles_femur_r_snapped.txt
NMSBuilder/Muscles_femur_l_snapped.txt
```

### 4. Modify the scaled OpenSim model

Run:

```matlab
MATLAB functions/modifyOsimModel.m
```

This script:

- loads the scaled LaiUhlrich2022 OpenSim model,
- reads the snapped NMSBuilder landmark files,
- converts coordinates from mm to m,
- replaces femur muscle path point locations,
- replaces femur wrap-object origins,
- transforms femur wrap-object rotations using the updated femur offset frame,
- applies `0.001` mesh scale factors,
- updates hip and knee joint frames using STAPLE coordinate systems,
- transforms femur mass-centre and inertia properties,
- updates femur marker locations in the marker set.

The main outputs are:

```text
OpenSim/LaiUhlrich2022_adjusted.osim
OpenSim/LaiUhlrich2022_markers_augmenter_adjusted.xml
```

## Paths Users Must Edit

The scripts currently contain absolute Windows paths from the original development machine. Before running them, edit the settings sections at the top of each script, especially:

```matlab
generic_osim_model_file
scaled_osim_model_file
snapped_landmark_folder
updated_osim_model_file
generic_marker_set_file
updated_marker_set_file
datasets_folder
output_models_folder
```

For a reusable GitHub repository, it is recommended to replace these absolute paths with paths relative to the repository root.

## Limitations

- The scripts are specific to right and left femurs.
- The OpenSim model must use compatible naming.
- The workflow assumes the muscle and wrap-object names in the NMSBuilder text files match the OpenSim model exactly.
- The scripts were developed for this thesis workflow and should be validated carefully before being reused for another subject or model.

## Acknowledgement

If using this material, cite the underlying tools and methods:

- Modenese, L. and Renault, J.-B. (2021). Automatic generation of personalised skeletal models of the lower limb from three-dimensional bone geometries. *Journal of Biomechanics*, 116, 110186. https://doi.org/10.1016/j.jbiomech.2020.110186.
- Valente, G., Crimi, G., Vanella, N., Schileo, E. and Taddei, F. (2017). nmsBuilder: Freeware to create subject-specific musculoskeletal models for OpenSim. *Computer Methods and Programs in Biomedicine*, 152, 85-92. https://doi.org/10.1016/j.cmpb.2017.09.012.
- Modenese, L., Montefiori, E., Wang, A., Wesarg, S., Viceconti, M. and Mazza, C. (2018). Investigation of the dependence of joint contact forces on musculotendon parameters using a codified workflow for image-based modelling. *Journal of Biomechanics*, 73, 108-118. https://doi.org/10.1016/j.jbiomech.2018.03.039.
- Seth, A., Hicks, J. L., Uchida, T. K., Habib, A., Dembia, C. L., Dunne, J. J., Ong, C. F., DeMers, M. S., Rajagopal, A., Millard, M., Hamner, S. R., Arnold, E. M., Yong, J. R., Lakshmikanth, S. K., Sherman, M. A., Ku, J. P. and Delp, S. L. (2018). OpenSim: Simulating musculoskeletal dynamics and neuromuscular control to study human and animal movement. *PLOS Computational Biology*, 14(7), e1006223. https://doi.org/10.1371/journal.pcbi.1006223.
- Modenese, L., Montefiori, E., Wang, A., Wesarg, S., Viceconti, M. and Mazza, C. (2018). Investigation of the dependence of joint contact forces on musculotendon parameters using a codified workflow for image-based modelling. *Journal of Biomechanics*, 73, 108-118. https://doi.org/10.1016/j.jbiomech.2018.03.039.
- Uhlrich, S. D., Jackson, R. W., Seth, A., Kolesar, J. A. and Delp, S. L. (2022). Muscle coordination retraining inspired by musculoskeletal simulations reduces knee contact force. *Scientific Reports*, 12(1), 9842. https://doi.org/10.1038/s41598-022-13386-9.

