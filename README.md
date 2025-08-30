# SimHub - Farming Simulator 22 - Extended Script

A custom SimHub script that extends raw data support and adds compatibility for modded values (e.g., from the Guidance Steering Mod), offering more flexibility and customization compared to the default SimHub FS22 integration or SimDashboard.

![In-game screenshot of Farming Simulator 22 using the dashboard](https://github.com/Sebastian7870/SimHub_FS22_ExtendedScript/blob/main/previewImage_Ingame.jpg)

![Screenshot of the adapted Vario Terminal Dashboard](https://github.com/Sebastian7870/SimHub_FS22_ExtendedScript/blob/main/previewImage.png)

<br>

## Introduction

I was never fully satisfied with SimDashboard because it cannot display modded values from the game, such as ProSeed, Guidance Steering, or others. After looking for alternatives, I discovered **SimHub**, which allows much more flexibility.  

However, SimHub’s default FS22 integration provides only a limited set of game data. To solve this, I modified the script so that it now sends a wide range of **raw data** from the game to SimHub. This allows you to use all relevant values to build and customize your own dashboards.  

The script includes support for important mods like **Guidance Steering**, **VCA**, **ProSeed**, **CombineXP**, and **BalerCounter**.  

I have been using both the dashboard and the script for a long time. Even though Farming Simulator 25 has been released, I decided to upload both the dashboard and the script here so that you can use them as well. The script can also be adapted for FS25 fairly easily if you are familiar with scripting.  

<br>

## Installation / Download

1. Download and install **SimHub** from the official website: [https://www.simhubdash.com/](https://www.simhubdash.com/)  
2. On this repository’s **[Releases page](https://github.com/Sebastian7870/SimHub_FS22_ExtendedScript/releases)**, download the files:  
   - `FS22_SHTelemetry_EDIT.zip`  
   - `S7870 Fendt Varioterminal.simhubdash`  
3. Move the file `FS22_SHTelemetry_EDIT.zip` into your Farming Simulator 22 mods folder:  
   `C:\Users\[YourUsername]\Documents\My Games\FarmingSimulator2022\mods`  
4. Open **SimHub** and import the dashboard:  
   - Go to the **Dash Studio** page  
   - Press **"Import Dashboard"** and select `S7870 Fendt Varioterminal.simhubdash`  
5. Start **Farming Simulator 22**  
6. Make sure to activate the **"Farming Simulator Telemetry (EDIT)"** mod in the game for the corresponding savegame

<br>

## Using the Telemetry Data in SimHub

To display the values in your SimHub dashboards, I highly recommend using **JavaScript** within SimHub.  
For example, you can assign or return a telemetry value (such as _money_) to a text field like this:

```javascript
let value = NewRawData()?.Telemetry["money"] || 0;
return value;
````
![Screenshot showing SimHub Instructions](https://github.com/Sebastian7870/SimHub_FS22_ExtendedScript/blob/main/SimHub_Instructions.png)

<br>

## Documentation: Available Telemetry Data

The script currently provides the following telemetry data.  
Please note that all of this information is available in SimHub under the **"rawData"** section.


| Key Name                                         | Type     | Description / Context                                      | Source / Mod |
|--------------------------------------------------|---------|------------------------------------------------------------|--------------|
| money                                            | Number  | Player's money                                             | Base Game    |
| dayTime                                          | Number  | Time of day in seconds                                     | Base Game    |
| day                                              | Number  | Current day                                                | Base Game    |
| timeScale                                        | Float   | Time scale                                                 | Base Game    |
| playTime                                         | Number  | Playtime                                                   | Base Game    |
| currentDayInPeriod                               | Number  | Day within the current period                               | Base Game    |
| currentPeriod                                    | Number  | Current period                                             | Base Game    |
| currentPeriodName                                | String  | Name of the current period                                 | Base Game    |
| currentSeason                                    | Number  | Current season                                             | Base Game    |
| currentYear                                      | Number  | Current year                                               | Base Game    |
| currentWeather                                   | Number  | Current weather                                            | Base Game    |
| nextWeather                                      | Number  | Weather forecast                                           | Base Game    |
| currentTemperatureInC                             | Number  | Temperature in °C                                         | Base Game    |
| isInVehicle                                      | Bool     | Player is in vehicle                                       | Base Game    |
| vehicleName                                      | String   | Vehicle name                                               | Base Game    |
| isMotorStarted                                   | Bool     | Engine running                                             | Base Game    |
| isReverseDriving                                 | Bool     | Reverse driving active                                     | Base Game    |
| isReverseDirection                               | Bool     | Vehicle is moving backwards                                 | Base Game    |
| maxRpm                                           | Number  | Maximum engine RPM                                         | Base Game    |
| minRpm                                           | Number  | Minimum engine RPM                                         | Base Game    |
| Rpm                                              | Number  | Current engine RPM                                         | Base Game    |
| speed                                            | Float   | Vehicle speed                                              | Base Game    |
| fuelLevel                                        | Number  | Fuel level                                                 | Base Game    |
| fuelCapacity                                     | Number  | Fuel capacity                                              | Base Game    |
| lastFuelUsage                                    | Float   | Last fuel usage                                            | Base Game    |
| ptoRPM                                           | Number  | PTO (Power Take-Off) RPM                                   | Base Game    |
| mass                                             | Float   | Vehicle mass                                               | Base Game    |
| massTotal                                        | Float   | Total mass including trailers etc.                         | Base Game    |
| motorTemperature                                 | Number  | Engine temperature                                         | Base Game    |
| motorFanEnabled                                  | Bool     | Radiator fan active                                        | Base Game    |
| cruiseControlMaxSpeed                            | Number  | Cruise control max speed                                   | Base Game    |
| cruiseControlActive                              | Bool     | Cruise control active                                      | Base Game    |
| leftTurnIndicator                                | Bool     | Left turn indicator                                        | Base Game    |
| rightTurnIndicator                               | Bool     | Right turn indicator                                       | Base Game    |
| beaconLightsActive                               | Bool     | Beacon lights active                                       | Base Game    |
| currentDirection                                 | Number  | Vehicle direction                                          | Base Game    |
| heading                                          | Float   | Vehicle heading                                            | Base Game    |
| farmlandID                                       | Number  | Field ID                                                   | Base Game    |
| vehicle_isPTOActive                              | Bool     | PTO active                                                 | Base Game    |
| vehicle_isUnfolded                               | Bool     | Vehicle unfolded                                           | Base Game    |
| vehicle_unfoldingState                            | Float   | Vehicle unfolding state                                     | Base Game    |
| hasFrontPTO                                      | Bool     | Front PTO available                                        | Base Game    |
| hasBackPTO                                       | Bool     | Rear PTO available                                         | Base Game    |
| fillLevel_[n]                                    | Number  | Fill level of material of implement n                      | Base Game    |
| fillLevelCapacity_[n]                            | Number  | Capacity for material of implement n                       | Base Game    |
| fillLevelPercentage_[n]                          | Float   | Fill level percentage of implement n                        | Base Game    |
| fillLevelMass_[n]                                | Float   | Mass of material of implement n                             | Base Game    |
| fillLevelName_[n]                                | String  | Name of material of implement n                              | Base Game    |
| selectableObjects_front                          | Number  | Number of front implements                                  | Base Game    |
| selectableObjects_back                           | Number  | Number of rear implements                                   | Base Game    |
| implement_front_name                             | String   | Front implement name                                        | Base Game    |
| implement_back_name                              | String   | Rear implement name                                         | Base Game    |
| implement_front_isLowered                        | Bool     | Front implement lowered                                     | Base Game    |
| implement_back_isLowered                         | Bool     | Rear implement lowered                                      | Base Game    |
| implement_front_isUnfolded                       | Bool     | Front implement unfolded                                    | Base Game    |
| implement_back_isUnfolded                        | Bool     | Rear implement unfolded                                     | Base Game    |
| implement_front_unfoldingState                   | Float   | Front implement unfolding state                              | Base Game    |
| implement_back_unfoldingState                    | Float   | Rear implement unfolding state                               | Base Game    |
| implement_front_isPTOActive                      | Bool     | Front PTO active                                            | Base Game    |
| implement_back_isPTOActive                       | Bool     | Rear PTO active                                             | Base Game    |
| implement_front_attacherJoint_moveAlpha          | Float   | Front attacher joint movement                               | Base Game    |
| implement_back_attacherJoint_moveAlpha           | Float   | Rear attacher joint movement                                | Base Game    |
| implement_front_workingWidth                     | Float   | Front implement working width                                | Base Game    |
| implement_back_workingWidth                      | Float   | Rear implement working width                                 | Base Game    |
| implement_index1_tippingState                    | Number  | Tipping state of implement 1                                 | Base Game    |
| implement_index1_tippingProgress                 | Number  | Tipping progress of implement 1                              | Base Game    |
| implement_index1_tipSideName                     | String   | Tip side of implement 1                                      | Base Game    |
| implement_index2_tippingState                    | Number  | Tipping state of implement 2                                 | Base Game    |
| implement_index2_tippingProgress                 | Number  | Tipping progress of implement 2                              | Base Game    |
| implement_index2_tipSideName                     | String   | Tip side of implement 2                                      | Base Game    |
| selectedObject_index                             | Number  | Index of selected implement                                  | Base Game    |
| selectedObject_isFrontloader                     | Bool     | Is selected implement a frontloader                           | Base Game    |
| implement_selected_name                           | String   | Name of selected implement                                     | Base Game    |
| implement_selected_isLowered                      | Bool     | Implement lowered                                              | Base Game    |
| implement_selected_isUnfolded                     | Bool     | Implement unfolded                                             | Base Game    |
| implement_selected_unfoldingState                 | Float   | Implement unfolding state                                       | Base Game    |
| implement_selected_isPTOActive                    | Bool     | PTO active                                                     | Base Game    |
| implement_selected_tippingState                   | Number  | Tipping state                                                  | Base Game    |
| implement_selected_tippingProgress                | Number  | Tipping progress                                               | Base Game    |
| implement_selected_tipSideName                    | String   | Tip side                                                       | Base Game    |
| implement_ridgeMarkerState                        | Number  | Ridge marker state                                             | Base Game    |
| implement_sessionBaleCounter                      | Number  | Bale counter (session)                                         | Base Game    |
| implement_lifetimeBaleCounter                     | Number  | Bale counter (total)                                           | Base Game    |
| implement_sessionWrappedBaleCounter               | Number  | Wrapped bale counter (session)                                 | Base Game    |
| implement_lifetimeWrappedBaleCounter              | Number  | Wrapped bale counter (total)                                   | Base Game    |
| implement_isSteeringAxleLocked                    | Bool     | Steering axle locked                                           | Base Game    |
| implement_currentWorkModeName                     | String   | Current work mode                                             | Base Game    |
| implement_isMoverConditioner                      | Bool     | Mower conditioner active                                       | Base Game    |
| implement_currentSeedSelectionName                | String   | Current seed selection                                        | Base Game    |
| implement_isCoverOn                               | Bool     | Cover active                                                   | Base Game    |
| combineXP_tonPerHour                              | Float    | Harvest throughput (tons/hour)                                 | Combine XPerience Mod |
| combineXP_engineLoad                              | Float    | Engine load                                                   | Combine XPerience Mod |
| combineXP_yield                                   | Float    | Yield                                                         | Combine XPerience Mod |
| combineXP_hasHighMoisture                         | Bool     | High moisture content                                         | Combine XPerience Mod |
| isSwathActive                                     | Bool     | Swath active                                                  | Base Game    |
| isSwathProducing                                  | Bool     | Swath being produced                                          | Base Game    |
| isFilling                                         | Bool     | Tank filling                                                  | Base Game    |
| workedHectares                                     | Float   | Worked hectares                                               | Base Game    |
| cutter_currentCutHeight                           | Float   | Current cut height                                            | Base Game    |
| pipe_currentState                                 | Number  | Pipe state                                                    | Base Game    |
| pipe_isFolding                                    | Bool     | Pipe is folding                                               | Base Game    |
| pipe_foldingState                                 | Float   | Pipe folding state                                            | Base Game    |
| pipe_overloadingState                             | Number   | Overloading state                                             | Base Game    |
| vca_isHandbrakeActive                             | Bool     | Handbrake active                                              | VCA Mod |
| vca_isDiffLockFrontActive                         | Bool     | Front differential lock active                                 | VCA Mod |
| vca_isDiffLockBackActive                          | Bool     | Rear differential lock active                                  | VCA Mod |
| vca_isAWDActive                                   | Bool     | All-wheel drive active                                        | VCA Mod |
| vca_isAWDFrontActive                              | Bool     | Front AWD active                                              | VCA Mod |
| vca_isKeepSpeedActive                             | Bool     | Cruise control active                                         | VCA Mod |
| vca_keepSpeed                                     | Float    | Target speed                                                 | VCA Mod |
| vca_keepSpeedTemp                                 | Float    | Temporary target speed                                       | VCA Mod |
| vca_slip                                          | Float    | Wheel slip                                                   | VCA Mod |
| vca_cruiseControlSpeed2                           | Number   | Second cruise control speed                                   | VCA Mod |
| vca_cruiseControlSpeed3                           | Number   | Third cruise control speed                                    | VCA Mod |
| gps_hasGuidanceSystem                             | Bool     | Vehicle has GPS guidance system                               | Guidance Steering Mod |
| gps_isGuidanceActive                              | Bool     | GPS guidance active                                           | Guidance Steering Mod |
| gps_isGuidanceSteeringActive                      | Bool     | GPS steering active                                           | Guidance Steering Mod |
| gps_currentLane                                   | Number   | Current lane                                                 | Guidance Steering Mod |
| gps_targetLaneDistanceDelta                       | Float    | Distance to target lane                                       | Guidance Steering Mod |
| gps_headingDelta                                  | Float    | GPS heading deviation                                         | Guidance Steering Mod |
| gps_laneWidth                                     | Float    | Lane width                                                   | Guidance Steering Mod |
| proSeed_tramLineMode                              | String   | Tramline mode                                                | ProSeed Mod |
| proSeed_tramLineDistance                          | Number   | Distance between tramlines                                    | ProSeed Mod |
| proSeed_currentLane                               | Number   | Current lane                                                 | ProSeed Mod |
| proSeed_maxLine                                   | Number   | Maximum number of tramlines                                    | ProSeed Mod |
| proSeed_createTramLines                           | Bool     | Tramlines being created                                       | ProSeed Mod |
| proSeed_allowFertilizer                           | Bool     | Fertilizer allowed                                            | ProSeed Mod |
| proSeed_sessionHectares                           | Float    | Area in current session                                       | ProSeed Mod |
| proSeed_totalHectares                             | Float    | Total area                                                    | ProSeed Mod |
| proSeed_hectarePerHour                            | Float    | Area per hour                                                 | ProSeed Mod |
| proSeed_seedUsage                                 | Float    | Seed usage                                                    | ProSeed Mod |
| proSeed_shutoffMode                               | Number   | Shutoff mode                                                  | ProSeed Mod |
| proSeed_shutoffModeText                           | String   | Shutoff mode description                                      | ProSeed Mod |
| proSeed_createPreMarkedTramLines                  | Bool     | Pre-marked tramlines active                                    | ProSeed Mod |
| proSeed_allowSound                                | Bool     | Sound allowed                                                 | ProSeed Mod |
| precisionFarming_cropSensor_isActive              | Bool     | Crop sensor active                                            | Precision Farming Mod |
| precisionFarming_soilTypeName                     | String   | Soil type name                                               | Precision Farming Mod |
| precisionFarming_isSprayAmountAutoModeActive      | Bool     | Automatic spray mode active                                    | Precision Farming Mod |
| precisionFarming_phActual                         | Number   | Current pH value                                              | Precision Farming Mod |
| precisionFarming_phTarget                         | Number   | Target pH value                                               | Precision Farming Mod |
| precisionFarming_phChanged                        | Number   | pH change                                                    | Precision Farming Mod |
| precisionFarming_applicationRate                  | Float    | Application rate                                             | Precision Farming Mod |
| precisionFarming_applicationRateFormattedString   | String   | Formatted application rate                                     | Precision Farming Mod |
| precisionFarming_nActual                          | Number   | Current nitrogen value                                        | Precision Farming Mod |
| precisionFarming_nTarget                          | Number   | Target nitrogen value                                         | Precision Farming Mod |
| precisionFarming_nitrogenChanged                  | Number   | Nitrogen change                                               | Precision Farming Mod |
| precisionFarming_litersPerHectar                  | Number   | Liters per hectare                                           | Precision Farming Mod |

