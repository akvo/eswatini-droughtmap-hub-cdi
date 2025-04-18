# -*- coding: utf-8 -*-
import os
from libs.config_reader import ConfigParser
from libs.statistics_operations import StatisticOperations
import libs.netcdf_functions as netcdf
# import numpy as np


class LandSurfaceTempRanking:
    """
    This is the core processing class for executing all Land-Surface Temperature ranking operations
    """
    def __init__(self):
        self.__config = ConfigParser()
        self.__stats = StatisticOperations()
        self.__output_dir = self.__config.get('output_dir').replace("\\", '/')
        self.__region = self.__config.get('region_name')
        self.__bounds = self.__config.get('bounds')
        self.__input_file = os.path.join(self.__output_dir, "STEP_0101_LST_anomaly_{}.nc".format(self.__region))
        self.__input_data_set = netcdf.open_dataset(self.__input_file)
        self.__latitudes = self.__config.get('latitudes')
        self.__longitudes = self.__config.get('longitudes')
        self.__times = self.__input_data_set.variables['time'][:]
        self.__number_of_months = len(self.__times)
        self.__missing = -9999.0
        # initialize the output file and prepare internal value lists #
        self.__initialize_ranking_file()

    def __initialize_ranking_file(self):
        self.__output_file = os.path.join(self.__output_dir, "STEP_0201_LST_anomaly_pct_rank_{}.nc".format(self.__region))
        output_data_set = None
        try:
            # create the output file #
            out_properties = {
                'latitudes': self.__latitudes,
                'longitudes': self.__longitudes,
                'times': self.__times,
                'time_units': 'days since 1900-01-01 00:00:00.0 UTC'
            }
            output_data_set = netcdf.initialize_dataset(self.__output_file, out_properties)

            # variables #
            lst_rank = output_data_set.createVariable('lst_anom_pct_rank', 'float32', ('time', 'latitude', 'longitude'))
            lst_rank.units = '1'
            lst_rank.missing_value = self.__missing
            lst_rank.standard_name = "lst_anomaly_pct_rank"
            lst_rank.long_name = "percent ranked LST anomaly"
        except IOError as ioe:
            print(ioe)
        except Exception as ex:
            print(ex)
        finally:
            if output_data_set is not None:
                output_data_set.close()

    def rank_parameter(self, index):
        output_data_set = None
        try:
            # determine the number of years for the month #
            years = int(self.__number_of_months / 12)
            if index < (self.__number_of_months % 12):
                years += 1
            # load the data for the current month #
            data = []
            t = index  # set the input time to the starting index
            for y in range(0, years):
                data.append(netcdf.extract_data(self.__input_data_set, 'lst_anom', t))
                t += 12  # increment by 1 year
            # rank the data by year #
            ranked_data = self.__stats.rank_parameter(data)
            # open file for appending #
            output_data_set = netcdf.open_dataset(self.__output_file, 'a')
            # loop thru the years and set the data to the correct time index #
            t = index
            for y in range(0, len(ranked_data)):
                output_data_set.variables['lst_anom_pct_rank'][t] = ranked_data[y]
                t += 12
        except IOError:
            raise
        except Exception:
            raise
        finally:
            if output_data_set is not None:
                output_data_set.close()


def main():
    """
    This is the main entry point for the program
    """
    # initialize a new LST Ranking class #
    rankings = LandSurfaceTempRanking()
    # loop thru the months and rank the LST anomalies #
    print("Ranking LST anomaly data...")
    for index in range(0, 12):
        rankings.rank_parameter(index)


if __name__ == '__main__':
    main()
